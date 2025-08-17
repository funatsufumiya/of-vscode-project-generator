#!/bin/bash

##
## << How to install >>
## $ git clone https://github.com/funatsufumiya/of-vscode-project-generator
## $ cd of-vscode-project-generator
## $ chmod +x of-vscode-project-generator.sh
## $ cp of-vscode-project-generator.sh /usr/local/bin/of-vscode-project-generator
##

echo
echo "======================================"
echo "   of-vscode-project-generator v0.0.6"
echo "======================================"
echo
echo "Usage:"
echo "  $ of-vscode-project-generator /path/to/apps/myApps/xxx"
echo "    or"
echo "  $ cd /path/to/apps/myApps/xxx && of-vscode-project-generator"
echo

realpath ()
{
    f=$@;
    if [ -d "$f" ]; then
        base="";
        dir="$f";
    else
        base="/$(basename "$f")";
        dir=$(dirname "$f");
    fi;
    dir=$(cd "$dir" && /bin/pwd);
    echo "$dir$base"
}

parse_addon_excludes() {
    local addon_path
    addon_path=$(realpath "$1")
    addon_path="$(echo "$addon_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    local exclude_file="$addon_path/addon_config.mk"
    if [ -f "$exclude_file" ]; then
        while IFS= read -r line; do
            line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [[ -z "$line" || "$line" == \#* ]] && continue
            if [[ "$line" == ADDON_SOURCES_EXCLUDE* ]] || [[ "$line" == ADDON_INCLUDES_EXCLUDE* ]]; then
                pat=$(echo "$line" | sed -E 's/^[^=+]+(\+=|=)[[:space:]]*//')
                pat="$(echo "$pat" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                [[ -z "$pat" || "$pat" == "=" ]] && continue
                pat="${pat//%/*}"
                echo "$addon_path/$pat"
            fi
        done < "$exclude_file"
    fi
}

# if -h or -v is given, show help or version
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    exit 0
fi

if [ "$1" = "-v" ] || [ "$1" = "--version" ]; then
    exit 0
fi

echo "------"
echo

if [ "$(uname)" == 'Darwin' ]; then
  OS='Mac'
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  OS='Linux'
elif [ "$(expr substr $(uname -s) 1 10)" == 'MINGW32_NT' ]; then                                                                                           
  OS='Win32'
elif [ "$COMSPEC" != "" ]; then
  OS='Win32'
fi

echo "[Info] OS: $OS"
proj=$(realpath $1)
echo "[Info] project path: '$proj'"

cd $proj

if [ ! -e "./src/ofApp.h" ]; then
    echo "[Warning] This directory seems not to be valid app path!"
    read -p "  Are you sure to proceed? (Y/n): " YN
    if [ ! "${YN}" = "Y" ]; then
        echo "cancelled."
        exit 1;
    fi
fi

if [ -e "./.vscode/c_cpp_properties.json" ]; then
    echo "[Warning] '.vscode/c_cpp_properties.json' already exists!"
    read -p "  Are you sure to proceed? (Y/n): " YN
    if [ ! "${YN}" = "Y" ]; then
        echo "cancelled."
        exit 1;
    fi
fi

if [ ! -d "../../../apps" ]; then
    _path=$(realpath ../../../)
    echo "[Error] '$_path' is not OF root. Stops."
    exit 1;
fi

OF_ROOT=../../..

path_list_file=$(mktemp)

MAC_SDK_ROOT="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

if [ "$OS" == 'Mac' ]; then
    # FIXME: consider iOS project
    if [ -d "$MAC_SDK_ROOT" ]; then
        echo "$MAC_SDK_ROOT/usr/include" >> $path_list_file
    fi
fi

echo "$OF_ROOT/libs/openFrameworks" >> $path_list_file
echo "$OF_ROOT/libs/openFrameworks/__" >> $path_list_file
#echo "$OF_ROOT/libs" >> $path_list_file

if [ -d "$OF_ROOT/libs" ]; then
    for i in $(ls $OF_ROOT/libs); do
        if [[ ! $i == "openFrameworks" ]]; then
            p="$OF_ROOT/libs/$i"
            if [ -d $p/include ]; then
                echo "$p/include" >> $path_list_file

                if [[ $i == "cairo" ]]; then
                    echo "$p/include/__" >> $path_list_file
                fi
            fi
        fi
    done
fi

if [ -e addons.make ]; then
    echo "[Info] Reading addons.make"
    for addon in $(cat addons.make); do
        # remove new line or carriage return
        addon=$(echo $addon | tr -d '\r\n')

        # if addon is empty, skip
        if [ -z $addon ]; then
            continue
        fi

        addon_path=$addon
        if [[ ! $addon == addons/* ]]; then
            addon_path=$OF_ROOT/addons/$addon
        fi

        if [ ! -d $addon_path ]; then
            echo "[Error] '$addon_path' doesn't exist. Stops."
            exit 1
        fi

        echo "[Info] Cheking '$addon_path'"

        # if [ -d $addon_path/src ]; then
        #     echo "$addon_path/src" >> $path_list_file
        #     echo "$addon_path/src/__" >> $path_list_file
        # fi

        excludes=()
        while IFS= read -r line; do
            excludes+=("$line")
        done < <(parse_addon_excludes "$addon_path")

        # echo "[Debug] excludes for $addon_path:"
        # for ex in "${excludes[@]}"; do
        #     echo "  $ex"
        # done

        if [ -d $addon_path/src ]; then
            for dir in $(find $addon_path/src -type d); do
                dir_abs=$(realpath "$dir")
                skip=0
                for ex in "${excludes[@]}"; do
                    if [[ "$dir_abs" == $ex ]]; then
                        skip=1
                        break
                    fi
                done
                if [ $skip -eq 0 ]; then
                    echo "$dir" >> $path_list_file
                fi
            done
        fi

        # if [ -d $addon_path/libs ]; then
        #     for lib in $(ls $addon_path/libs); do
        #         lib_path=$addon_path/libs/$lib
        #         if [ -d $lib_path/src ]; then
        #             echo "$lib_path/src" >> $path_list_file
        #         fi
        #         if [ -d $lib_path/include ]; then
        #             echo "$lib_path/include" >> $path_list_file
        #         fi
        #     done # end for libs
        # fi

        if [ -d $addon_path/libs ]; then
            for lib in $(ls $addon_path/libs); do
                lib_path=$addon_path/libs/$lib
                if [ -d $lib_path/src ]; then
                    for dir in $(find $lib_path/src -type d); do
                        dir_abs=$(realpath "$dir")
                        skip=0
                        for ex in "${excludes[@]}"; do
                            # echo "[Debug] $dir_abs $ex"
                            if [[ "$dir_abs" == $ex ]]; then
                                skip=1
                                break
                            fi
                        done
                        if [ $skip -eq 0 ]; then
                            echo "$dir" >> $path_list_file
                        fi
                    done
                fi
                if [ -d $lib_path/include ]; then
                    for dir in $(find $lib_path/include -type d); do
                        dir_abs=$(realpath "$dir")
                        skip=0
                        for ex in "${excludes[@]}"; do
                            if [[ "$dir_abs" == $ex ]]; then
                                skip=1
                                break
                            fi
                        done
                        if [ $skip -eq 0 ]; then
                            echo "$dir" >> $path_list_file
                        fi
                    done
                fi
            done # end for libs
        fi
    done # end for addons.make
fi

list=$(mktemp)
sp="                "

echo "[Info] Generating..."
echo "$sp\"\${workspaceFolder}/**\"," >> $list
echo "$sp\"\${workspaceFolder}/src\"," >> $list
echo "$sp\"\${workspaceFolder}/src/**\"," >> $list

for i in $(cat $path_list_file); do

    r=$(realpath $i)
    r=$(echo $r | sed -e 's/^\/c/C:/')

    if [[ $r == *__ ]]; then
        r=$(echo $r | sed -e 's/__$/**/')
    fi

    echo "$sp\"$r\"," >> $list

    # WORKAROUND: if ofxOsc/libs/oscpack/src is hit, also oscpack/src/**
    if [[ $r == *oscpack/src ]]; then
        echo "$sp\"$r/**\"," >> $list
    fi

done # end for path_list_file

mac_framework_list_file=$(mktemp)
if [ "$OS" == 'Mac' ]; then
    # FIXME: consider iOS project
    if [ -d "$MAC_SDK_ROOT" ]; then
        echo "$MAC_SDK_ROOT/System/Library/Frameworks" >> $mac_framework_list_file
    fi
fi

mac_framework_list=$(mktemp)
line_count=$(wc -l < "$mac_framework_list_file")
current=1
for i in $(cat $mac_framework_list_file); do

    r=$(realpath $i)
    # r=$(echo $r | sed -e 's/^\/c/C:/')

    if [[ $r == *__ ]]; then
        r=$(echo $r | sed -e 's/__$/**/')
    fi

    if [ $current -lt $line_count ]; then
        echo "$sp\"$r\"," >> $mac_framework_list
    else
        echo "$sp\"$r\"" >> $mac_framework_list
    fi
    current=$((current + 1))

done # end for mac_framework_list_file

# consider x64 or arm64
# first check uname exists, if not, use x64 as default
arch="x64"
if [ -x "$(command -v uname)" ]; then
    if [ "$(uname -m)" == "arm64" ]; then
        arch="arm64"
    fi
fi

echo "$sp\"\${workspaceFolder}\"" >> $list

f=$(cat << EOS
{
    "configurations": [
        {
            "name": "$(echo $OS)",
            "includePath": [
$(cat $list)
            ],
            "defines": [],
            "macFrameworkPath": [
$(cat $mac_framework_list)
            ],
            "cStandard": "c11",
            "cppStandard": "c++17",
            "intelliSenseMode": "clang-$(echo $arch)"
        }
    ],
    "version": 4
}
EOS
)

mkdir -p ./.vscode
touch ./.vscode/c_cpp_properties.json
echo $f > ./.vscode/c_cpp_properties.json
echo "[Info] Done!"
echo "[Info] Saved to '$proj/.vscode/c_cpp_properties.json' :)"