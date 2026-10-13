use super::protocol::*;
use anyhow::{bail, ensure, Result};
use std::{
    io::{BufReader, Read, Write},
    os::unix::net::UnixStream,
    time::Duration,
};
pub fn request(command: Command) -> Result<Response> {
    let mut stream = UnixStream::connect(SOCKET)?;
    stream.set_read_timeout(Some(Duration::from_secs(25)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;
    write_json(
        &mut stream,
        &Request {
            version: VERSION,
            command,
        },
    )?;
    let r: Response = read_json_limit(&mut BufReader::new(stream), 32 << 20)?;
    ensure!(r.version == VERSION, "protocol version mismatch");
    if let Some(e) = &r.error {
        bail!("{e}; current task: {}", serde_json::to_string(&r.snapshot)?)
    }
    Ok(r)
}
pub fn upload(id: u64, token: String, mut input: impl Read) -> Result<()> {
    let mut stream = UnixStream::connect(SOCKET)?;
    stream.set_write_timeout(Some(Duration::from_secs(60)))?;
    write_json(
        &mut stream,
        &Request {
            version: VERSION,
            command: Command::Input { id, token },
        },
    )?;
    let reply: Response = read_json(&mut BufReader::with_capacity(1, &mut stream))?;
    ensure!(reply.error.is_none(), "input rejected: {:?}", reply.error);
    let mut buffer = [0u8; 65536];
    loop {
        let n = input.read(&mut buffer)?;
        stream.write_all(&(n as u32).to_be_bytes())?;
        if n == 0 {
            break;
        }
        stream.write_all(&buffer[..n])?;
    }
    Ok(())
}
pub fn wait(id: u64, mut snapshot: Snapshot) -> Result<Task> {
    loop {
        let task = snapshot
            .task
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("missing task"))?;
        ensure!(task.id == id, "task was replaced; requested task {id}");
        if !task.active {
            return Ok(task.clone());
        }
        request(Command::Watch {
            after: snapshot.sequence,
        })?;
        snapshot = request(Command::Task { id })?.snapshot;
    }
}
pub fn command(args: Vec<String>) -> Result<()> {
    match args.first().map(String::as_str).unwrap_or("help") {
        "help" => {
            println!("Rust recovery client. All operations run in mobile-recovery-daemon.\nCommands: capabilities, status [--json], task TASK_ID, watch, cancel TASK_ID, shell\nprepare-install --check|--confirm-erase-userdata (A/B)\nformat-root --check|--confirm\nprepare-boot --check|--confirm (single slot)\nsafe-ufs\ninstall-initial MANIFEST REGISTRATION SYSTEM MIN_BYTES --check|--confirm|--resume-check|--resume-confirm\ndeploy-query MANIFEST SYSTEM\ndeploy-offline MANIFEST SYSTEM MISSING_COUNT --confirm\nmount-target [--ro|--rw], target-status, unmount-target\nrebuild boot [nixos-rebuild build options]\ngenerations, select-generation NUMBER --confirm\nupdate-firmware|update-recovery IMAGE --check|--confirm\ndeploy-check-boot\nclear-boot-request --check|--confirm\nrepair-backup-gpt --check|--confirm\nrepair-filesystems --check|--confirm\nreboot-system|reboot-recovery|reboot-bootloader|poweroff --confirm\nInput transfers are framed; CLI disconnection after complete input does not cancel installation.");
            Ok(())
        }
        "capabilities" => {
            println!(
                "{}",
                serde_json::to_string_pretty(&request(Command::Capabilities)?)?
            );
            Ok(())
        }
        "status" => {
            println!(
                "{}",
                serde_json::to_string_pretty(&request(Command::Status)?.snapshot)?
            );
            Ok(())
        }
        "watch" => {
            let mut after = 0;
            loop {
                let r = request(Command::Watch { after })?;
                after = r.snapshot.sequence;
                println!("{}", serde_json::to_string(&r.snapshot)?);
                if r.snapshot.task.is_some_and(|t| !t.active) {
                    return Ok(());
                }
            }
        }
        "submit" => {
            ensure!(args.len() > 1, "use submit OPERATION ...");
            let args = args[1..].to_vec();
            let input = args[0] == "deploy-offline"
                || (args[0] == "install-initial" && args.last().is_some_and(|s| s == "--confirm"));
            println!(
                "{}",
                serde_json::to_string(&request(Command::Submit { args, input })?)?
            );
            Ok(())
        }
        "input" => {
            ensure!(args.len() == 3, "use input TASK_ID TOKEN");
            upload(args[1].parse()?, args[2].clone(), std::io::stdin().lock())
        }
        "task" => {
            ensure!(args.len() == 2, "use task TASK_ID");
            println!(
                "{}",
                serde_json::to_string(
                    &request(Command::Task {
                        id: args[1].parse()?
                    })?
                    .snapshot
                )?
            );
            Ok(())
        }
        "cancel" => {
            ensure!(args.len() == 2, "use cancel TASK_ID");
            request(Command::Cancel {
                id: args[1].parse()?,
            })?;
            Ok(())
        }
        "shell" => shell(),
        _ => {
            let input = args.first().is_some_and(|a| a == "deploy-offline")
                || (args.first().is_some_and(|a| a == "install-initial")
                    && args.last().is_some_and(|a| a == "--confirm"));
            let r = request(Command::Submit { args, input })?;
            let id = r.snapshot.task.as_ref().unwrap().id;
            eprintln!("Recovery task {id}");
            if let Some(token) = r.token {
                if let Err(e) = upload(id, token, std::io::stdin().lock()) {
                    eprintln!("Transfer failed: {e:#}; querying task {id}");
                }
            }
            let task = wait(id, r.snapshot)?;
            if let Some(e) = task.error {
                bail!("task {id}: {e}")
            }
            if let Some(result) = task.result {
                print!("{result}");
                if !result.ends_with('\n') {
                    println!();
                }
            }
            Ok(())
        }
    }
}
fn shell() -> Result<()> {
    println!("Recovery Rust shell. Type help for operations, exit to disconnect.");
    let mut line = String::new();
    loop {
        print!("recovery> ");
        std::io::stdout().flush()?;
        line.clear();
        if std::io::stdin().read_line(&mut line)? == 0 {
            return Ok(());
        }
        let args = parse_line(&line)?;
        if args.is_empty() {
            continue;
        }
        if args == ["exit"] {
            return Ok(());
        }
        if args[0] == "shell" {
            eprintln!("already in recovery shell");
            continue;
        }
        if let Err(e) = command(args) {
            eprintln!("{e:#}");
        }
    }
}
pub fn parse_line(s: &str) -> Result<Vec<String>> {
    let mut args = Vec::new();
    let mut word = String::new();
    let mut quote = None;
    let mut escape = false;
    let mut present = false;
    for c in s.trim_end().chars() {
        if escape {
            word.push(c);
            escape = false;
            present = true;
            continue;
        }
        if c == '\\' && quote != Some('\'') {
            escape = true;
            continue;
        }
        if let Some(q) = quote {
            if c == q {
                quote = None
            } else {
                word.push(c)
            }
            present = true;
        } else if c == '\'' || c == '"' {
            quote = Some(c);
            present = true;
        } else if c.is_whitespace() {
            if present {
                args.push(std::mem::take(&mut word));
                present = false;
            }
        } else {
            word.push(c);
            present = true;
        }
    }
    ensure!(!escape && quote.is_none(), "unterminated quote or escape");
    if present {
        args.push(word);
    }
    Ok(args)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shell_quotes_are_arguments_without_evaluation() {
        assert_eq!(
            parse_line("rebuild boot --flake 'path with spaces' \"$(false)\"").unwrap(),
            vec!["rebuild", "boot", "--flake", "path with spaces", "$(false)"]
        );
        assert!(parse_line("'unfinished").is_err());
    }
}
