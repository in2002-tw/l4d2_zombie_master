#!/bin/bash

# L4D2 Zombie Master Compilation Script
# This script compiles the SourceMod plugin

# Load local environment if available
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

SCRIPT_DIR="left4dead2/addons/sourcemod/scripting"
PLUGIN_DIR="build"
GAMEDATA_DIR="left4dead2/addons/sourcemod/gamedata"
PLUGINS=("l4d2_zombie_master")

echo "========================================="
echo "L4D2 Zombie Master Compilation Script"
echo "========================================="
echo ""

# Find spcomp: use SPCOMP env var, then PATH, then common locations
if [ -n "$SPCOMP" ] && [ -f "$SPCOMP" ]; then
    : # SPCOMP already set by environment
elif command -v spcomp &> /dev/null; then
    SPCOMP="spcomp"
else
    echo "ERROR: spcomp compiler not found!"
    echo ""
    echo "Options:"
    echo "1. Add spcomp to your PATH"
    echo "2. Set the SPCOMP environment variable: export SPCOMP=/path/to/spcomp"
    echo "3. Download from: https://www.sourcemod.net/downloads.php"
    echo ""
    exit 1
fi

# Create directories if they don't exist
mkdir -p "$PLUGIN_DIR"

# Compile all plugins
COMPILE_SUCCESS=true

for PLUGIN_NAME in "${PLUGINS[@]}"; do

    echo "Compiling $PLUGIN_NAME.sp..."
    echo ""

    # Compile the plugin
    "$SPCOMP" -v2 -E \
        -i"$SCRIPT_DIR/include" \
        -i".ci/includes" \
        "$SCRIPT_DIR/$PLUGIN_NAME.sp" \
        -o"$PLUGIN_DIR/$PLUGIN_NAME.smx"

    # Check if compilation was successful
    if [ $? -ne 0 ]; then
        COMPILE_SUCCESS=false
        echo "✗ Failed to compile $PLUGIN_NAME"
        echo ""
    else
        echo "✓ Compiled: $PLUGIN_DIR/$PLUGIN_NAME.smx"
        echo ""
    fi
done

# Copy to server if compilation successful
if [ "$COMPILE_SUCCESS" = true ]; then
    echo ""
    echo "========================================="
    echo "Compilation successful!"
    echo "========================================="
    echo ""

    # Copy to L4D2 server (set L4D2_SERVER_DIR to enable)
    L4D2_SERVER_DIR="${L4D2_SERVER_DIR:-}"
    SERVER_PLUGIN_DIR="$L4D2_SERVER_DIR/addons/sourcemod/plugins"
    SERVER_GAMEDATA_DIR="$L4D2_SERVER_DIR/addons/sourcemod/gamedata"

    if [ -n "$L4D2_SERVER_DIR" ] && [ -d "$SERVER_PLUGIN_DIR" ]; then
        echo "Copying to L4D2 server..."

        # Copy plugins
        for PLUGIN_NAME in "${PLUGINS[@]}"; do
            if [ -f "$PLUGIN_DIR/$PLUGIN_NAME.smx" ]; then
                cp "$PLUGIN_DIR/$PLUGIN_NAME.smx" "$SERVER_PLUGIN_DIR/"
                if [ $? -eq 0 ]; then
                    echo "✓ Plugin copied: $SERVER_PLUGIN_DIR/$PLUGIN_NAME.smx"
                fi
            fi
        done

        # Copy gamedata files
        if [ -d "$GAMEDATA_DIR" ] && [ -d "$SERVER_GAMEDATA_DIR" ]; then
            cp "$GAMEDATA_DIR"/*.txt "$SERVER_GAMEDATA_DIR/" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "✓ Gamedata files copied to: $SERVER_GAMEDATA_DIR/"
            fi
        fi

        # Copy cfg files
        SERVER_CFG_DIR="$L4D2_SERVER_DIR/cfg/sourcemod"
        CFG_DIR="left4dead2/cfg/sourcemod"
        if [ -d "$CFG_DIR" ] && [ -d "$SERVER_CFG_DIR" ]; then
            cp -r "$CFG_DIR"/. "$SERVER_CFG_DIR/"
            if [ $? -eq 0 ]; then
                echo "✓ Config files copied to: $SERVER_CFG_DIR/"
            fi
        fi

        # Copy translations
        SERVER_TRANSLATIONS_DIR="$L4D2_SERVER_DIR/addons/sourcemod/translations"
        TRANSLATIONS_DIR="left4dead2/addons/sourcemod/translations"
        if [ -d "$TRANSLATIONS_DIR" ] && [ -d "$SERVER_TRANSLATIONS_DIR" ]; then
            cp -r "$TRANSLATIONS_DIR"/. "$SERVER_TRANSLATIONS_DIR/"
            if [ $? -eq 0 ]; then
                echo "✓ Translations copied to: $SERVER_TRANSLATIONS_DIR/"
            fi
        fi

        # Copy models (GridRenderer Prop backend needs models/grid/*)
        SERVER_MODELS_DIR="$L4D2_SERVER_DIR/models"
        MODELS_DIR="left4dead2/models"
        if [ -d "$MODELS_DIR" ] && [ -d "$SERVER_MODELS_DIR" ]; then
            cp -r "$MODELS_DIR"/. "$SERVER_MODELS_DIR/"
            if [ $? -eq 0 ]; then
                echo "✓ Models copied to: $SERVER_MODELS_DIR/"
            fi
        fi

        # Copy materials (textures/VMTs referenced by the above models)
        SERVER_MATERIALS_DIR="$L4D2_SERVER_DIR/materials"
        MATERIALS_DIR="left4dead2/materials"
        if [ -d "$MATERIALS_DIR" ] && [ -d "$SERVER_MATERIALS_DIR" ]; then
            cp -r "$MATERIALS_DIR"/. "$SERVER_MATERIALS_DIR/"
            if [ $? -eq 0 ]; then
                echo "✓ Materials copied to: $SERVER_MATERIALS_DIR/"
            fi
        fi

        echo ""
        echo "To reload plugins, use:"
        for PLUGIN_NAME in "${PLUGINS[@]}"; do
            echo "  sm plugins reload $PLUGIN_NAME"
        done
    else
        echo "Server directory not found: $SERVER_PLUGIN_DIR"
        echo "Manual installation required:"
        echo "1. Copy the 'left4dead2/addons' folder to your L4D2 server directory"
        echo "2. Restart the server or use 'sm plugins load <plugin_name>'"
    fi
    echo ""
else
    echo ""
    echo "========================================="
    echo "Compilation failed!"
    echo "========================================="
    echo ""
    echo "Please check the errors above and fix them."
    echo ""
    exit 1
fi
