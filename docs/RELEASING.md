# Releasing

Releases are built locally so they carry the same code signature every time. macOS ties a user's Accessibility grant to the signature, so a build signed with a different identity would make everyone re-grant access after updating.

1. Update `VERSION` and add an entry to `CHANGELOG.md`.
2. Build the packages (universal, signed with your `Scrollo Local Signing` identity if present):

   ```sh
   ./scripts/package.sh
   ```

   This writes `dist/Scrollo-<version>.dmg` and `.zip` and prints their SHA-256 checksums.
3. Commit, tag and push:

   ```sh
   git commit -am "Release v1.0.0"
   git tag v1.0.0 && git push origin main --tags
   ```
4. Publish the GitHub release with the packages attached:

   ```sh
   gh release create v1.0.0 dist/Scrollo-1.0.0.dmg dist/Scrollo-1.0.0.zip \
     --title "Scrollo 1.0.0" --notes-file docs/release-notes/v1.0.0.md
   ```

## Notarization

Releases are **not notarized** because that needs a paid Apple Developer account; users go through *Open Anyway* once (see the README). If you have an account, sign with a Developer ID certificate and run `xcrun notarytool submit` followed by `xcrun stapler staple` on the DMG, then update the install instructions.
