# 🔍 Static Analysis Tool

A lightweight, container-based wrapper for running static application security testing (SAST) on local codebases or Git repositories.

This tool acts as a **reliable execution layer** over a SAST engine, ensuring:
- No modification of source code
- No loss of findings due to parsing
- Clean and reproducible scans

---

## 🚀 Installation

Make the installer executable and run it:

```bash
chmod +x ./install.sh
./install.sh
▶️ Usage

View all available options:

./main.sh -h
📌 Basic Examples
Scan a local project
./main.sh --file-path /path/to/project
Scan a Git repository
./main.sh --repo https://github.com/user/repo.git
Scan with email report
./main.sh \
  --file-path /path/to/project \
  --email you@example.com

If not specified, the tool automatically uses config/smtp.conf (if available).

Specify severity (optional)
./main.sh \
  --file-path /project \
  --severity HIGH,CRITICAL

By default, the tool performs a full scan (ALL severities).

⚙️ Configuration

SMTP configuration file:

config/smtp.conf

Example:

SMTP_SERVER="smtp.gmail.com"
SMTP_PORT="587"
SMTP_USER="your_email@gmail.com"
SMTP_PASS="your_app_password"
FROM_EMAIL="your_email@gmail.com"

The installer (install.sh) can create or update this file interactively.

📁 Project Structure
.
├── main.sh
├── install.sh
├── config/
│   └── smtp.conf
├── reports/
📄 Output
Reports are saved in:
reports/
Output is raw scanner output (unmodified)

Example:

reports/sast_YYYYMMDD_HHMMSS.txt
🧠 Features
✅ Container-based SAST execution
✅ Safe, non-destructive scanning (isolated copy via rsync)
✅ Raw output (no parsing, no filtering)
✅ Full scan by default (LOW → CRITICAL)
✅ Optional severity input (informational)
✅ Optional SMTP email delivery
✅ Auto-detects default config
✅ Retry logic for stability
⚠️ Requirements

Automatically installed via install.sh:

Docker
Git
Curl
Rsync
🛠️ Notes
This tool does NOT modify your source code
Uses a temporary isolated copy for scanning
Designed as a thin wrapper, not a scanner replacement
Output accuracy depends on the underlying SAST engine
✅ Quick Start
chmod +x ./install.sh
./install.sh

./main.sh --file-path ./your-project
📌 Tip

Always start with:

./main.sh -h
🎯 Use Cases
Security testing (VAPT)
Developer self-assessment
CI/CD pre-scan step
Bulk repository scanning
