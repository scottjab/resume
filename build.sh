#!/usr/bin/env bash
# Resume built with https://github.com/there4/markdown-resume
mkdir o
# build your own container.
docker run --platform linux/amd64 -v ${PWD}:/resume scottjab/markdown-resume md2resume html /resume/resume.md /resume/o/
mv o/resume.html .
cp resume.html index.html
rm -rf o