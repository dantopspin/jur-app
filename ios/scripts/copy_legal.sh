#!/bin/sh
# The app shows Terms and Privacy from its own bundle (offline, inside the app).
# After editing legal/*.html for the website, run this from ios/ and rebuild.
set -e
cp ../legal/terms.html Jur/Resources/Legal/terms.html
cp ../legal/privacy.html Jur/Resources/Legal/privacy.html
echo "copied terms.html and privacy.html into Jur/Resources/Legal"
