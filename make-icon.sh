#!/bin/sh
# Builds the app icon asset catalog from AppIcon.png before the Xcode project is generated.
set -e
mkdir -p Assets.xcassets/AppIcon.appiconset
cp AppIcon.png Assets.xcassets/AppIcon.appiconset/AppIcon.png
cat > Assets.xcassets/Contents.json <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > Assets.xcassets/AppIcon.appiconset/Contents.json <<'JSON'
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# Apple Watch app icon
mkdir -p Watch/Assets.xcassets/AppIcon.appiconset
cp AppIcon.png Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cat > Watch/Assets.xcassets/Contents.json <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > Watch/Assets.xcassets/AppIcon.appiconset/Contents.json <<'JSON'
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# Alternate app icons (one per theme) plus small previews for the theme picker
for f in Icons/AppIcon-*.png; do
  name=$(basename "$f" .png)
  mkdir -p "Assets.xcassets/$name.appiconset" "Assets.xcassets/Preview-${name#AppIcon-}.imageset"
  cp "$f" "Assets.xcassets/$name.appiconset/$name.png"
  cat > "Assets.xcassets/$name.appiconset/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "$name.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  cp "$f" "Assets.xcassets/Preview-${name#AppIcon-}.imageset/preview.png"
  cat > "Assets.xcassets/Preview-${name#AppIcon-}.imageset/Contents.json" <<JSON
{
  "images" : [ { "filename" : "preview.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done
mkdir -p Assets.xcassets/Preview-Default.imageset
cp AppIcon.png Assets.xcassets/Preview-Default.imageset/preview.png
cat > Assets.xcassets/Preview-Default.imageset/Contents.json <<'JSON'
{
  "images" : [ { "filename" : "preview.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
