# Test VaultCard on an iPhone without a Mac

GitHub Actions can compile the native iOS app on a hosted Mac. You can download that build on Windows and use AltStore with AltServer to sign and install it on your iPhone.

## Build and download the IPA

1. Open the repository on GitHub and select **Actions**.
2. Choose **Native iOS iPhone Build**.
3. Select `main` in the branch selector, then choose **Run workflow** to build the latest commit on `main`. The workflow also runs automatically when files under `ios-native/` change on `main`.
4. Open the completed run and download the **VaultCard-iphone-unsigned** artifact. Extract the downloaded artifact ZIP to get `VaultCard-iphone-unsigned.ipa`.

The IPA contains an unsigned device build. It cannot be installed directly; AltStore must re-sign it first. The workflow does not need your Apple ID, password, or signing certificates.

## Sign and install from Windows

1. Install AltServer for Windows and AltStore on your iPhone using the [official Windows setup instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Connect the iPhone to the same Wi-Fi network as the Windows PC, or connect it by USB.
2. Use AltStore on the iPhone to add the extracted `VaultCard-iphone-unsigned.ipa` and install the signed app. Use the same Apple ID used for the current VaultCard installation. Follow AltStore's prompts for your Apple ID; those credentials are used by the local signing flow, not entered into GitHub Actions.
3. A free Apple developer account can be used for personal sideloading; a paid developer membership is not required. Free provisioning expires after 7 days, so refresh the app with AltStore before it expires. Keep AltServer available for refreshes. See [AltStore’s refresh instructions](https://faq.altstore.io/altstore-classic/your-altstore). TestFlight requires paid Apple Developer Program membership and is not part of this workflow.

## Protect an existing VaultCard install

The current app bundle identifier is `com.vaultcard.ios`, with signing team `2829H6AD46`. AltStore may modify the app identifier when signing, so using the same Apple ID alone does not guarantee an in-place update.

Do **not** uninstall an existing VaultCard copy to try this build. First verify that the installed app and the AltStore-signed build have a compatible bundle identifier and signing identity, and confirm the app's data migration or update behavior. A different bundle identifier or signing setup can prevent access to the existing app's local data or keychain. Keep the existing VaultCard installation available until you have confirmed that the new install opens with the data you need.

If the build cannot update the installed copy, stop before removing the existing app and resolve the signing or data migration path first.
