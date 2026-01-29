#!/bin/bash
set -e

HOPS_BIN="${HOPS_BIN:-.build/debug/hops}"
RESULTS_FILE="Tests/Results/network-test-results.md"

echo "Testing network capabilities..."
echo "Using binary: $HOPS_BIN"
echo ""

mkdir -p Tests/Results

cat >"$RESULTS_FILE" <<'EOF'
# Network Capability Test Results

**Test Date**: $(date)
**Binary**: $HOPS_BIN

## Test Summary

EOF

test_disabled() {
	echo "Test 1: Network disabled (should fail)"
	echo "### Test 1: Network Disabled" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"
	echo "**Expected**: External network requests should fail" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"

	if $HOPS_BIN run --network disabled /tmp -- /bin/sh -c "wget -T 2 -O /dev/null http://example.com 2>&1" >/tmp/test-disabled.log 2>&1; then
		echo "❌ FAIL: Network disabled test - request succeeded when it should have failed"
		echo "**Result**: ❌ FAIL - Network request succeeded when it should have failed" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-disabled.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		return 1
	else
		echo "✓ PASS: Network disabled works"
		echo "**Result**: ✓ PASS - Network request blocked as expected" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-disabled.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	fi
	echo "" >>"$RESULTS_FILE"
}

test_loopback() {
	echo "Test 2: Network loopback"
	echo "### Test 2: Network Loopback" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"
	echo "**Expected**: Loopback (127.0.0.1) should work, external requests should fail" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"

	echo "  2a. Testing loopback interface (127.0.0.1)"
	if $HOPS_BIN run --network loopback /tmp -- /bin/sh -c "ping -c 1 127.0.0.1" >/tmp/test-loopback-local.log 2>&1; then
		echo "  ✓ PASS: Loopback interface works"
		echo "**Result 2a**: ✓ PASS - Loopback interface accessible" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-loopback-local.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	else
		echo "  ❌ FAIL: Loopback interface not working"
		echo "**Result 2a**: ❌ FAIL - Loopback interface not accessible" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-loopback-local.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	fi
	echo "" >>"$RESULTS_FILE"

	echo "  2b. Testing external network (should fail)"
	if $HOPS_BIN run --network loopback /tmp -- /bin/sh -c "wget -T 2 -O /dev/null http://example.com 2>&1" >/tmp/test-loopback-external.log 2>&1; then
		echo "  ❌ FAIL: External network accessible in loopback mode"
		echo "**Result 2b**: ❌ FAIL - External network accessible when it should be blocked" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-loopback-external.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	else
		echo "  ✓ PASS: External network blocked"
		echo "**Result 2b**: ✓ PASS - External network blocked as expected" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-loopback-external.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	fi
	echo "" >>"$RESULTS_FILE"
}

test_outbound() {
	echo "Test 3: Network outbound"
	echo "### Test 3: Network Outbound" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"
	echo "**Expected**: External network requests should succeed" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"

	if $HOPS_BIN run --network outbound /tmp -- /bin/sh -c "wget -T 5 -O /dev/null http://example.com 2>&1" >/tmp/test-outbound.log 2>&1; then
		echo "✓ PASS: Outbound network works"
		echo "**Result**: ✓ PASS - External network accessible" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-outbound.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	else
		echo "❌ FAIL: Outbound network not working"
		echo "**Result**: ❌ FAIL - External network not accessible" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-outbound.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	fi
	echo "" >>"$RESULTS_FILE"
}

test_full() {
	echo "Test 4: Network full"
	echo "### Test 4: Network Full" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"
	echo "**Expected**: All network access should work" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"

	if $HOPS_BIN run --network full /tmp -- /bin/sh -c "wget -T 5 -O /dev/null http://example.com 2>&1" >/tmp/test-full.log 2>&1; then
		echo "✓ PASS: Full network works"
		echo "**Result**: ✓ PASS - Full network access working" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-full.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	else
		echo "❌ FAIL: Full network not working"
		echo "**Result**: ❌ FAIL - Full network access not working" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-full.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	fi
	echo "" >>"$RESULTS_FILE"
}

test_dns() {
	echo "Test 5: DNS resolution (outbound mode)"
	echo "### Test 5: DNS Resolution" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"
	echo "**Expected**: DNS queries should resolve in outbound/full modes" >>"$RESULTS_FILE"
	echo "" >>"$RESULTS_FILE"

	if $HOPS_BIN run --network outbound /tmp -- /bin/sh -c "nslookup example.com 2>&1" >/tmp/test-dns.log 2>&1; then
		echo "✓ PASS: DNS resolution works"
		echo "**Result**: ✓ PASS - DNS resolution working" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-dns.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	else
		echo "❌ FAIL: DNS resolution not working"
		echo "**Result**: ❌ FAIL - DNS resolution not working" >>"$RESULTS_FILE"
		echo "" >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
		cat /tmp/test-dns.log >>"$RESULTS_FILE"
		echo "\`\`\`" >>"$RESULTS_FILE"
	fi
	echo "" >>"$RESULTS_FILE"
}

test_disabled
test_loopback
test_outbound
test_full
test_dns

echo ""
echo "Network tests complete!"
echo "Results written to: $RESULTS_FILE"

cat >>"$RESULTS_FILE" <<'EOF'

## Configuration Details

### Network Capability Modes

1. **disabled**: No network interfaces configured
2. **loopback**: Only loopback interface (127.0.0.1)
3. **outbound**: NAT interface (10.0.0.5/24) with DNS (8.8.8.8, 8.8.4.4)
4. **full**: Same as outbound (NAT + DNS)

### Implementation

Network configuration is handled in `CapabilityEnforcer.swift`:
- Lines 58-81: `configureNetwork()` function
- disabled/loopback: `config.interfaces = []`
- outbound/full: NAT interface with gateway 10.0.0.1

### Recommendations

EOF

echo "Test execution completed at $(date)" >>"$RESULTS_FILE"
