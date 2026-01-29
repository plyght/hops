use crate::models::policy::Policy;
use std::fs;
use std::io;
use std::path::PathBuf;

pub fn get_profiles_dir() -> io::Result<PathBuf> {
    let home = dirs::home_dir()
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "Could not find home directory"))?;

    let profiles_dir = home.join(".hops").join("profiles");

    if !profiles_dir.exists() {
        fs::create_dir_all(&profiles_dir)?;
    }

    Ok(profiles_dir)
}

pub fn load_profiles() -> io::Result<Vec<Policy>> {
    let profiles_dir = get_profiles_dir()?;
    let mut profiles = Vec::new();

    if let Ok(entries) = fs::read_dir(profiles_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("toml") {
                if let Ok(content) = fs::read_to_string(&path) {
                    if let Ok(mut policy) = toml::from_str::<Policy>(&content) {
                        policy.name = path
                            .file_stem()
                            .and_then(|s| s.to_str())
                            .unwrap_or("unnamed")
                            .to_string();
                        profiles.push(policy);
                    }
                }
            }
        }
    }

    Ok(profiles)
}

pub fn save_profile(name: &str, policy: &Policy) -> io::Result<()> {
    let profiles_dir = get_profiles_dir()?;
    let file_path = profiles_dir.join(format!("{}.toml", name));

    let toml_content = toml::to_string_pretty(policy)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    fs::write(file_path, toml_content)?;
    Ok(())
}
