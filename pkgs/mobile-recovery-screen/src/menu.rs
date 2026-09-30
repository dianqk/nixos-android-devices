use std::time::{Duration, Instant};

pub(crate) const KEY_VOLUMEUP: u16 = 115;
pub(crate) const KEY_VOLUMEDOWN: u16 = 114;
pub(crate) const KEY_POWER: u16 = 116;

#[derive(Default)]
pub(crate) struct Menu {
    pub selected: usize,
    pub confirming: bool,
    pub yes: bool,
    pub busy: bool,
    pub error: bool,
    pub logs: bool,
    pub updates: bool,
    pub held: u8,
    pub chord: bool,
    pub pressed: [Option<Instant>; 3],
}
impl Menu {
    pub fn reset_keys(&mut self) {
        self.held = 0;
        self.chord = false;
        self.pressed = [None; 3];
    }
    pub fn key(&mut self, code: u16, value: i32, now: Instant, len: usize) -> Option<usize> {
        let key = match code {
            KEY_VOLUMEUP => 0,
            KEY_VOLUMEDOWN => 1,
            KEY_POWER => 2,
            _ => return None,
        };
        if self.busy || value == 2 {
            return None;
        }
        let bit = 1 << key;
        if value == 1 {
            if self.held & bit == 0 {
                if self.held != 0 {
                    self.chord = true;
                }
                self.held |= bit;
                self.pressed[key] = Some(now);
            }
            return None;
        }
        if value != 0 || self.held & bit == 0 {
            return None;
        }
        self.held &= !bit;
        let held_for = self.pressed[key]
            .take()
            .and_then(|t| now.checked_duration_since(t));
        let valid = !self.chord
            && held_for
                .is_some_and(|d| d >= Duration::from_millis(30) && d < Duration::from_millis(1500));
        if self.held == 0 {
            self.chord = false;
        }
        if !valid {
            return None;
        }
        if self.logs {
            self.logs = false;
            return None;
        }
        if self.updates {
            self.updates = false;
            return None;
        }
        if self.error {
            self.error = false;
            self.confirming = false;
            self.yes = false;
            return None;
        }
        if key != 2 {
            if self.confirming {
                self.yes = !self.yes;
            } else {
                self.selected = (self.selected + if key == 0 { len - 1 } else { 1 }) % len;
            }
        } else if !self.confirming && self.selected == 0 {
            self.logs = true;
        } else if !self.confirming {
            self.confirming = true;
            self.yes = false;
        } else if !self.yes {
            self.confirming = false;
        } else {
            self.busy = true;
            return Some(self.selected);
        }
        None
    }
}
