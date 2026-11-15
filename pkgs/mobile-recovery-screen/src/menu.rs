use std::time::{Duration, Instant};

pub(crate) const KEY_VOLUMEUP: u16 = 115;
pub(crate) const KEY_VOLUMEDOWN: u16 = 114;
pub(crate) const KEY_POWER: u16 = 116;

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum KeyResult {
    None,
    Wake,
    Action(usize),
}

#[derive(Default)]
pub(crate) struct Menu {
    pub selected: usize,
    pub confirming: bool,
    pub yes: bool,
    pub busy: bool,
    pub error: bool,
    pub logs: bool,
    pub updates: bool,
    /// Item that first asks for one of `choices` (the Android userdata size).
    pub choice_item: Option<usize>,
    pub choosing: bool,
    pub choices: Vec<String>,
    /// Index into `choices`; `choices.len()` selects Cancel.
    pub choice: usize,
    /// Plan lines of the chosen size (its sized check), shown before the
    /// final confirmation.
    pub plan: Vec<String>,
    /// The result view (`error`) shows a successful action's output.
    pub succeeded: bool,
    pub held: u8,
    pub chord: bool,
    pub pressed: [Option<Instant>; 3],
    pub wake_press: bool,
    pub suppressed: u8,
}
impl Menu {
    /// The chosen value while confirming a choice item.
    pub fn chosen(&self) -> Option<&str> {
        (self.choosing && self.confirming)
            .then(|| self.choices.get(self.choice).map(String::as_str))
            .flatten()
    }
    pub fn reset_keys(&mut self) {
        self.held = 0;
        self.chord = false;
        self.pressed = [None; 3];
        self.wake_press = false;
        self.suppressed = 0;
    }
    pub fn suppress_actions(&mut self) {
        // Operation/status transitions invalidate pending menu actions without
        // losing a Power press already dedicated to waking the screen.
        self.suppressed |= self.held;
    }
    pub fn key(
        &mut self,
        code: u16,
        value: i32,
        now: Instant,
        len: usize,
        blanked: bool,
        input_locked: bool,
    ) -> KeyResult {
        let key = match code {
            KEY_VOLUMEUP => 0,
            KEY_VOLUMEDOWN => 1,
            KEY_POWER => 2,
            _ => return KeyResult::None,
        };
        if value == 2 {
            return KeyResult::None;
        }
        let bit = 1 << key;
        if value == 1 {
            if self.held & bit == 0 {
                if self.held != 0 {
                    self.chord = true;
                }
                self.held |= bit;
                self.pressed[key] = Some(now);
                if key == 2 {
                    self.wake_press = blanked;
                }
                if input_locked || self.busy || blanked {
                    self.suppressed |= bit;
                }
            }
            return KeyResult::None;
        }
        if value != 0 || self.held & bit == 0 {
            return KeyResult::None;
        }
        self.held &= !bit;
        let wake = key == 2 && (self.wake_press || blanked);
        if key == 2 {
            self.wake_press = false;
        }
        let suppressed = self.suppressed & bit != 0;
        self.suppressed &= !bit;
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
            return KeyResult::None;
        }
        // A wake press is consumed even if the screen was unblanked elsewhere
        // before release. It must never accept a stale destructive confirmation.
        if wake {
            return KeyResult::Wake;
        }
        if suppressed || input_locked || self.busy || blanked {
            return KeyResult::None;
        }
        if self.logs {
            self.logs = false;
            return KeyResult::None;
        }
        if self.updates {
            self.updates = false;
            return KeyResult::None;
        }
        if self.error {
            self.error = false;
            self.succeeded = false;
            self.confirming = false;
            self.choosing = false;
            self.yes = false;
            return KeyResult::None;
        }
        if self.choosing && !self.confirming {
            let options = self.choices.len() + 1;
            if key != 2 {
                self.choice = (self.choice + if key == 0 { options - 1 } else { 1 }) % options;
            } else if self.choice >= self.choices.len() {
                self.choosing = false;
            } else {
                self.confirming = true;
                self.yes = false;
            }
            return KeyResult::None;
        }
        if key != 2 {
            if self.confirming {
                self.yes = !self.yes;
            } else {
                self.selected = (self.selected + if key == 0 { len - 1 } else { 1 }) % len;
            }
        } else if !self.confirming && self.selected == 0 {
            self.logs = true;
        } else if !self.confirming && self.choice_item == Some(self.selected) {
            // The caller loads `choices`; the first one is preselected.
            self.choosing = true;
            self.choices.clear();
            self.choice = 0;
        } else if !self.confirming {
            self.confirming = true;
            self.yes = false;
        } else if !self.yes {
            self.confirming = false;
            self.choosing = false;
        } else {
            self.busy = true;
            return KeyResult::Action(self.selected);
        }
        KeyResult::None
    }
}
