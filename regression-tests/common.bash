#!/usr/bin/env bash

get_espresso_image_flag() {
    if [[ -n "${ESPRESSO_DEV:-}" ]]; then
        echo "--dev nitro"
    else
        echo "--latest-espresso-image"
    fi
}
