// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyGuard
 * @author Technical Research Synthesis Group
 * @notice A gas-optimized reentrancy guard that uses a single storage slot
 * with bitmasks to manage multiple locks. This is more efficient than
 * using a separate boolean for each function, especially for contracts
 * with several mutually exclusive, non-reentrant functions.
 */
abstract contract ReentrancyGuard {
    // A single storage slot to hold all reentrancy locks.
    // Each bit in the uint256 represents a lock for a specific function.
    uint256 private _status;

    // Define lock masks for clarity and to prevent magic numbers.
    uint256 internal constant _NOT_ENTERED = 0;
    uint256 internal constant _REVIVE_LOCK = 1;      // 2**0
    uint256 internal constant _PERSIST_LOCK = 2;     // 2**1
    uint256 internal constant _DECOMMISSION_LOCK = 4; // 2**2

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * @param lockMask The specific bitmask for the function being protected.
     */
    modifier nonReentrant(uint256 lockMask) {
        require(_status & lockMask == 0, "ReentrancyGuard: reentrant call");
        require(_status == _NOT_ENTERED, "ReentrancyGuard: another function is active");

        // Set the specific lock for this function.
        _status = lockMask;

        _;

        // Unset the lock after the call is complete.
        _status = _NOT_ENTERED;
    }
}
