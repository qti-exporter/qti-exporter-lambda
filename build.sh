#!/bin/bash

if ! docker info >/dev/null 2>&1; then
  echo "Docker does not seem to be running, run it first and retry"
  exit 1
fi

docker run -it --rm -v "$PWD":/var/task lambci/lambda:build-ruby2.7 bundle install --deployment

rm function.zip
zip -r function.zip lambda_function.rb vendor