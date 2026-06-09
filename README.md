# Offline Deployment Guide

This repository installs MongoDB and Ollama on a Linux machine without internet access.

It supports:

- MongoDB server offline installation
- MongoDB shell (`mongosh`) offline installation
- Ollama offline installation
- Ollama model restore from a copied local model store
- Combined install and remove using root-level master scripts

## Repository Layout

```text
AI-offline-deployment/
|- master-install.sh
|- master-remove.sh
|- Mongo-server-offline-installation/
|  |- install_mongodb_offline.sh
|  |- remove_mongodb_offline.sh
|  |- installation-src/
|- Ollama-server-installation/
|  |- install_ollama_offline.sh
|  |- install_ollama_models_offline.sh
|  |- remove_ollama_offline.sh
|  |- remove_ollama_models_offline.sh
|  |- installtion-src/
|     |- ollama-linux-amd64.tar.zst
|     |- Models/
|        |- models/
|           |- blobs/
|           |- manifests/
```

Note: `installtion-src` under `Ollama-server-installation` is spelled without the second `a`. Keep that folder name as-is unless you also change the scripts.

## What You Need To Download

### 1. MongoDB Server

Official download page:

- https://www.mongodb.com/try/download/community

Download one of these Linux offline artifact types for your target Linux distribution and CPU architecture:

- `.deb`
- `.rpm`
- `.tgz`
- `.tar.gz`

Examples:

- Ubuntu or Debian: download `.deb`
- RHEL, Rocky, AlmaLinux, CentOS, or SUSE: download `.rpm`
- Generic/manual install: download `.tgz` or `.tar.gz`

### 2. MongoDB Shell (`mongosh`)

Official download page:

- https://www.mongodb.com/try/download/shell

Download the Linux `mongosh` package that matches your target Linux distribution and CPU architecture.

Supported formats depend on what MongoDB provides for your platform, usually one of:

- `.deb`
- `.rpm`
- `.tgz`
- `.tar.gz`

Important: this repo expects a Mongo shell to be present after install. The Mongo installer fails if neither `mongosh` nor legacy `mongo` is available.

### 3. Ollama Binary Archive

Official download page:

- https://ollama.com/download/linux

The scripts are designed for an offline archive such as:

- `ollama-linux-amd64.tar.zst`
- or another Linux archive in `.tar.zst`, `.tgz`, or `.tar.gz`

If you use a different architecture, download the matching archive for that target machine.

### 4. Ollama Models

Official model library:

- https://ollama.com/library

You do not usually download a single model file manually from the library page. The normal process is:

1. On a machine with internet access, install Ollama.
2. Pull the model you want.
3. Copy the local Ollama model store.
4. Paste that copied model store into this repository.

Example on an internet-connected Linux machine:

```bash
ollama pull llama3.2
ollama pull qwen2.5-coder:7b
```

After pulling models, copy the local Ollama `models` folder.

Common source locations on the machine where you pulled the models:

- Linux service install: `/var/lib/ollama/models`
- Linux user install: `~/.ollama/models`
- Windows: `%USERPROFILE%\.ollama\models`
- macOS: `~/.ollama/models`

The copied folder must contain:

- `blobs/`
- `manifests/`

## Exactly Where To Paste The Downloaded Files

### MongoDB server package and `mongosh`

Paste both the MongoDB server package/archive and the Mongo shell package/archive into:

- `Mongo-server-offline-installation/installation-src/`

Example:

```text
Mongo-server-offline-installation/
|- install_mongodb_offline.sh
|- remove_mongodb_offline.sh
|- installation-src/
|  |- mongodb-linux-x86_64-...tgz
|  |- mongosh-...tgz
```

Notes:

- If you use `.deb`, put all required MongoDB and `mongosh` `.deb` files in the same `installation-src/` folder.
- If you use `.rpm`, put all required `.rpm` files in the same `installation-src/` folder.
- If you use archive files, place the MongoDB server archive and `mongosh` archive together in the same folder.
- The installer searches the script folder and `installation-src/`, but `installation-src/` is the cleanest place to keep the offline files.

### Ollama binary archive

Paste the Ollama archive into:

- `Ollama-server-installation/installtion-src/`

Example:

```text
Ollama-server-installation/
|- install_ollama_offline.sh
|- installtion-src/
|  |- ollama-linux-amd64.tar.zst
```

Notes:

- The script checks both `installation-src/` and `installtion-src/`.
- In this repo, the existing folder is `installtion-src/`, so use that folder.

### Ollama model bundle

Paste the copied Ollama model store so the final structure becomes:

- `Ollama-server-installation/installtion-src/Models/models/blobs/`
- `Ollama-server-installation/installtion-src/Models/models/manifests/`

Example:

```text
Ollama-server-installation/
|- installtion-src/
|  |- ollama-linux-amd64.tar.zst
|  |- Models/
|     |- models/
|        |- blobs/
|        |- manifests/
```

Important:

- Do not paste only the files inside `blobs` or only the files inside `manifests`.
- Copy the full `models` directory structure.
- If you paste the model store in a different place, you must set `OLLAMA_MODEL_BUNDLE` manually when running the model installer.

## Target Machine Requirements

Run these scripts on the target Linux machine.

Expected basics:

- Linux host
- `bash`
- `sudo` access or root user
- enough disk space for MongoDB and Ollama models
- `systemctl` or `service`

Additional requirements based on what you install:

- MongoDB archive installs need `tar`
- Ollama `.tar.zst` installs need `tar` and `zstd`

## How To Install Everything

From the repository root on the target Linux machine:

```bash
chmod +x master-install.sh
chmod +x Mongo-server-offline-installation/install_mongodb_offline.sh
chmod +x Ollama-server-installation/install_ollama_offline.sh
chmod +x Ollama-server-installation/install_ollama_models_offline.sh

sudo ./master-install.sh
```

What `master-install.sh` does:

1. Installs MongoDB if it is not already installed.
2. Installs Mongo shell if it is missing.
3. Writes the MongoDB connection string to `Mongo-server-offline-installation/mongo-connection-string.txt`.
4. Installs Ollama if it is not already installed.
5. Restores the copied Ollama model bundle.
6. Writes the Ollama endpoint to `Ollama-server-installation/ollama-endpoint.txt`.

## Default Values Used By The Master Installer

The root `master-install.sh` currently uses these MongoDB defaults:

- Username: `sampleUser`
- Password: `samplePassword`
- Port: `27017`
- Bind IP: `0.0.0.0`

The root `master-install.sh` currently uses these Ollama defaults:

- Host: `127.0.0.1`
- Port: `11434`

If you want different defaults, edit `master-install.sh` before running it.

## Files Created After Install

### MongoDB connection string

Saved to:

- `Mongo-server-offline-installation/mongo-connection-string.txt`

Expected format:

```text
mongodb://sampleUser:samplePassword@<host>:27017/admin?authSource=admin
```

### Ollama endpoint

Saved to:

- `Ollama-server-installation/ollama-endpoint.txt`

Expected format:

```text
http://127.0.0.1:11434
```

## Install Individual Components

### Install only MongoDB

```bash
chmod +x Mongo-server-offline-installation/install_mongodb_offline.sh
sudo MONGO_ADMIN_USER=appuser MONGO_ADMIN_PASSWORD='StrongPassword!' \
  ./Mongo-server-offline-installation/install_mongodb_offline.sh
```

Optional environment variables:

- `MONGO_PACKAGE`
- `MONGO_PORT`
- `MONGO_BIND_IP`
- `MONGO_PUBLIC_HOST`
- `MONGO_ADMIN_USER`
- `MONGO_ADMIN_PASSWORD`
- `MONGO_DB_PATH`
- `CONNECTION_FILE`

### Install only Ollama runtime

```bash
chmod +x Ollama-server-installation/install_ollama_offline.sh
sudo ./Ollama-server-installation/install_ollama_offline.sh
```

Optional environment variables:

- `OLLAMA_PACKAGE`
- `OLLAMA_PORT`
- `OLLAMA_BIND_HOST`
- `OLLAMA_PUBLIC_HOST`
- `OLLAMA_MODELS_PATH`
- `OLLAMA_LOG_PATH`
- `OLLAMA_ENV_FILE`
- `CONNECTION_FILE`

### Restore only Ollama models

```bash
chmod +x Ollama-server-installation/install_ollama_models_offline.sh
sudo ./Ollama-server-installation/install_ollama_models_offline.sh
```

Optional environment variables:

- `OLLAMA_MODEL_BUNDLE`
- `OLLAMA_MODELS_PATH`

## How To Remove Everything

To remove all installed components:

```bash
chmod +x master-remove.sh
sudo ./master-remove.sh --all
```

### Remove only MongoDB runtime

```bash
sudo ./master-remove.sh --mongo
```

### Remove only Ollama runtime

```bash
sudo ./master-remove.sh --ollama
```

### Remove only Ollama models

```bash
sudo ./master-remove.sh --ollama-models
```

### Remove MongoDB data files too

By default, MongoDB removal preserves `/var/lib/mongo`.

To remove MongoDB data also:

```bash
sudo REMOVE_DATA=true ./master-remove.sh --mongo
```

### Remove Ollama models from the runtime path too

By default, Ollama runtime removal preserves `/var/lib/ollama`.

To remove models together with runtime:

```bash
sudo REMOVE_MODELS=true ./Ollama-server-installation/remove_ollama_offline.sh
```

Or use the dedicated model remover:

```bash
sudo ./master-remove.sh --ollama-models
```

## Quick Checklist

Before running install, confirm:

- MongoDB server package/archive is in `Mongo-server-offline-installation/installation-src/`
- `mongosh` package/archive is in `Mongo-server-offline-installation/installation-src/`
- Ollama archive is in `Ollama-server-installation/installtion-src/`
- Copied Ollama model store is in `Ollama-server-installation/installtion-src/Models/models/`
- You are running on the target Linux machine, not on Windows
- The downloaded files match the target machine architecture

## Recommended Download Workflow

1. On an internet-connected machine, download MongoDB server from the MongoDB Community Server page.
2. Download `mongosh` from the MongoDB Shell page.
3. Download the Ollama Linux archive.
4. Install Ollama on a connected machine and run `ollama pull <model-name>` for the models you need.
5. Copy the pulled Ollama `models` directory.
6. Paste all files into the exact repository locations listed above.
7. Move the repository to the offline Linux machine.
8. Run `sudo ./master-install.sh`.

## Troubleshooting

### Error: Mongo shell not found

Cause:

- `mongosh` was not copied into `Mongo-server-offline-installation/installation-src/`

Fix:

- Download `mongosh` from https://www.mongodb.com/try/download/shell
- Paste it into `Mongo-server-offline-installation/installation-src/`
- Run the installer again

### Error: No local Ollama archive found

Cause:

- The Ollama archive is missing or pasted in the wrong folder

Fix:

- Paste the archive into `Ollama-server-installation/installtion-src/`

### Error: No offline Ollama model store found next to this script

Cause:

- The copied model store does not match the expected `Models/models/blobs` and `Models/models/manifests` structure

Fix:

- Paste the full copied `models` folder into `Ollama-server-installation/installtion-src/Models/`

### Error: archive targets the wrong architecture

Cause:

- You downloaded `amd64` files for an `arm64` machine, or the opposite

Fix:

- Download artifacts that match the target Linux CPU architecture

## Summary

If you only need the shortest answer:

- Download MongoDB server from https://www.mongodb.com/try/download/community and paste it into `Mongo-server-offline-installation/installation-src/`
- Download `mongosh` from https://www.mongodb.com/try/download/shell and paste it into `Mongo-server-offline-installation/installation-src/`
- Download the Ollama Linux archive from https://ollama.com/download/linux and paste it into `Ollama-server-installation/installtion-src/`
- Pull models from https://ollama.com/library on an internet-connected machine, then copy the resulting `models` folder into `Ollama-server-installation/installtion-src/Models/`
- Run `sudo ./master-install.sh` on the target Linux machine