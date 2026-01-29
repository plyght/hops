#!/bin/bash

echo "Testing interactive shell prompt..."
echo "=================================="
echo ""

echo "Test 1: Running /bin/sh - should show prompt immediately"
echo "Commands to execute: ls, pwd, echo hello, exit"
echo ""

(
  sleep 1
  echo "ls"
  sleep 1
  echo "pwd"
  sleep 1
  echo "echo hello"
  sleep 1
  echo "exit"
) | .build/debug/hops run /tmp -- /bin/sh

echo ""
echo "Test completed!"
