#[cfg(windows)]
mod host;
#[cfg(windows)]
mod path_access;

fn main() {
    #[cfg(windows)]
    match host::run() {
        Ok(code) => std::process::exit(code as i32),
        Err(error) => {
            eprintln!("marea: isolated AI worker could not start: {error}");
            std::process::exit(3);
        }
    }
    #[cfg(not(windows))]
    {
        eprintln!("marea: this isolation host requires Windows");
        std::process::exit(3);
    }
}
