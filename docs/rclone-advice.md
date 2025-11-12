# Setting up rclone

## Install

```bash
brew install rclone
```

Or download latest rclone: [https://rclone.org/downloads/](https://rclone.org/downloads/)

## Creating an Encrypted Remote on google drive

3 steps:

1. Create an unencrypted remote
1. Set up oauth for that remote
1. Create an encrypted remote as a sub-folder on the unencrypted remote

### Create a new Remote (unencrypted)

```bash
rclone config
n # for New Remote
# Enter name for new remote, e.g `gdrive`.
15 # for Google Drive (Not Google Cloud Storage) (Double check the number, it might have changed)
```

### Create your client_id

1. Go to [https://console.developers.google.com/](https://console.developers.google.com/)
1. Create a New Project
   . Under “ENABLE APIS AND SERVICES”:
   a. Search for “Drive"
   a. nable the “Google Drive API”
1. Click “Create credentials”, then “Desktop App”.
   a. Select "Google Drive API"
   a. Select "User data" then "Save and Continue"
1. Under OAuth Client ID:
   a. Application type = "Desktop App"
   a. client name = "secureLocal".
1. Go to Credentials tab
   a. click on the oAuth 2.0 Client ID
   a. Copy Client ID
1. Testing tab: add your email as a test user
   a. else you'll get "permission denied" at login

### Return to the cli

1. Provide credentials:
   a. Paste the Client ID
   a. Copy and paste Client Secret
1. Scope `1`
   1, Enter a string value for the root folder
1. Service_account_file = blank
1. Edit the advanced config (y/n) - `n`
1. Use auto config? `y`

### Sign in to Google

1. This opens the sign-on page for Google Drive. If not, visit [http://127.0.0.1:53682/auth](http://127.0.0.1:53682/auth)

### Return to the cli again

1. Configure a Team Drive? `n`
1. Finalized version of config is shown. `y` # to accept

### Phew!

`rclone` config file has been created

1. `rclone config show` should list your new unencrypted remote

## Creating the encrypted remote

```bash
rclone config
```

1. `n` to create a new remote
1. Choose a name, e.g. "crypt" for the new encrypted remote.
1. `crypt`
1. `gdrive:/crypt` to add the encrypted folder "crypt" to your gdrive remote.
1. `1` to choose full filename encryption
1. `1` to choose full folder encryption
1. `y` to choose your own password
1. Choose a password, and enter twice for confirmation.
   a. Make a note of this. Lose it and you can't get your data back.
1. Choose a salt pass word, and enter twice for confirmation.
1. `n` to ignore advanced config
1. `y` to confirm remote config is correct
1. `q` to quit
