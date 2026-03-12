# Publishing to GitHub

## Prerequisites

1. GitHub account
2. Git configured with your credentials
3. GitHub CLI (optional) or web browser

## Option 1: Using GitHub CLI (gh)

```bash
cd /home/estevec/crio-seccomp-experiment

# Login to GitHub
gh auth login

# Create repository and push
gh repo create crio-seccomp-experiment --public --source=. --remote=origin --push

# View on GitHub
gh repo view --web
```

## Option 2: Using Git + GitHub Web

### Step 1: Create Repository on GitHub

1. Go to https://github.com/new
2. Repository name: `crio-seccomp-experiment`
3. Description: "Experiment demonstrating CRI-O seccomp notifier for logging blocked syscalls"
4. Choose Public
5. Do NOT initialize with README (we already have one)
6. Click "Create repository"

### Step 2: Push Local Repository

```bash
cd /home/estevec/crio-seccomp-experiment

# Add remote (replace YOUR_USERNAME with your GitHub username)
git remote add origin https://github.com/YOUR_USERNAME/crio-seccomp-experiment.git

# Push to GitHub
git branch -M main
git push -u origin main
```

## Option 3: Using SSH

```bash
cd /home/estevec/crio-seccomp-experiment

# Add remote with SSH (replace YOUR_USERNAME)
git remote add origin git@github.com:YOUR_USERNAME/crio-seccomp-experiment.git

# Push
git branch -M main
git push -u origin main
```

## Verify Upload

Visit: `https://github.com/YOUR_USERNAME/crio-seccomp-experiment`

You should see:
- README.md displayed on the main page
- All files listed
- Commit history

## Add Topics (Optional)

On GitHub repository page:
1. Click the gear icon next to "About"
2. Add topics: `kubernetes`, `cri-o`, `seccomp`, `security`, `containers`, `syscalls`
3. Save changes

## Repository Structure

```
crio-seccomp-experiment/
├── README.md              # Main documentation
├── QUICKREF.md           # Quick reference
├── DEEP_DIVE.md          # Detailed explanation
├── METRICS.md            # Metrics configuration
├── pod.yaml              # Test pod manifest
├── seccomp-test.c        # Test program
├── node-shell.yaml       # Debug pod manifest
├── Dockerfile            # Optional container build
├── run-experiment.sh     # Automation script
└── .gitignore           # Git ignore rules
```

## Sharing

Share your repository:
```
https://github.com/YOUR_USERNAME/crio-seccomp-experiment
```

## License (Optional)

Consider adding a license:

```bash
cd /home/estevec/crio-seccomp-experiment

# Create LICENSE file (example: MIT)
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

git add LICENSE
git commit -m "Add MIT license"
git push
```
