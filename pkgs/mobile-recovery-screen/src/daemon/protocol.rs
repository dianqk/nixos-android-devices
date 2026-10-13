//! Versioned local control messages; input frames are a separate task-bound channel.
use anyhow::{ensure, Result};
use serde::{Deserialize, Serialize};
use std::io::{BufRead, Read, Write};
pub const SOCKET: &str = "/run/mobile-recovery/control.sock";
pub const VERSION: u32 = 1;
pub const MAX_MESSAGE: usize = 65536;
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub version: u32,
    pub command: Command,
}
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Command {
    Capabilities,
    Status,
    Task {
        id: u64,
    },
    Watch {
        after: u64,
    },
    Cancel {
        id: u64,
    },
    Submit {
        args: Vec<String>,
        #[serde(default)]
        input: bool,
    },
    Input {
        id: u64,
        token: String,
    },
}
#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct Snapshot {
    pub sequence: u64,
    pub task: Option<Task>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Task {
    pub id: u64,
    pub operation: String,
    pub target: String,
    pub phase: String,
    pub active: bool,
    pub cancellable: bool,
    pub cancelled: bool,
    pub completed: u64,
    pub total: Option<u64>,
    pub logs: Vec<String>,
    pub result: Option<String>,
    pub error: Option<String>,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct Response {
    pub version: u32,
    pub snapshot: Snapshot,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capabilities: Option<Vec<String>>,
}
pub fn read_json<T: serde::de::DeserializeOwned>(r: &mut impl BufRead) -> Result<T> {
    read_json_limit(r, MAX_MESSAGE)
}
pub fn read_json_limit<T: serde::de::DeserializeOwned>(
    r: &mut impl BufRead,
    limit: usize,
) -> Result<T> {
    let mut line = Vec::new();
    let n = r.take((limit + 1) as u64).read_until(b'\n', &mut line)?;
    ensure!(
        n > 0 && n <= limit && line.last() == Some(&b'\n'),
        "invalid control message length"
    );
    Ok(serde_json::from_slice(&line)?)
}
pub fn write_json(w: &mut impl Write, v: &impl Serialize) -> Result<()> {
    serde_json::to_writer(&mut *w, v)?;
    w.write_all(b"\n")?;
    w.flush()?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn request_roundtrip_and_bounds() {
        for command in [
            Command::Status,
            Command::Task { id: 3 },
            Command::Watch { after: 4 },
            Command::Submit {
                args: vec!["format-root".into(), "--check".into()],
                input: false,
            },
            Command::Input {
                id: 9,
                token: "abc".into(),
            },
        ] {
            let request = Request {
                version: VERSION,
                command,
            };
            let mut bytes = Vec::new();
            write_json(&mut bytes, &request).unwrap();
            let _: Request = read_json(&mut bytes.as_slice()).unwrap();
        }
        assert!(read_json::<Request>(
            &mut &b"{\"version\":1,\"command\":{\"action\":\"status\"},\"surprise\":true}\n"[..]
        )
        .is_err());
        assert!(read_json::<Request>(
            &mut &b"{\"version\":1,\"command\":{\"action\":\"status\"}}"[..]
        )
        .is_err());
        assert!(read_json::<Request>(&mut vec![b' '; MAX_MESSAGE + 1].as_slice()).is_err());
    }
}
