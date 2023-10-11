#!/bin/bash

uncommited=$(git ls-files -d -m -o --exclude-standard --directory --no-empty-directory)
if [[ -z "$uncommited" ]];
then
  exit 0
else
  echo "::group::Uncommited changes detected"
  echo "$uncommited"
  echo "::endgroup::"
  exit 1
fi
