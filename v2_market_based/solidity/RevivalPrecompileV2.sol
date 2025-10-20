// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ReentrancyGuard.sol";
import "./WitnessValidator.sol";

/**
 * @title RevivalPrecompileV2
 * @author Technical Research Synthesis Group
 * @notice This contract is the Solidity interface for the native State Revival Precompile.
 * It manages the lifecycle of expired state: ephemeral revival, persistence, and decommissioning.
 *
 * ARCHITECTURE: CONDITIONAL PERSISTENCE
 * 1. revive: Verifies a Verkle proof and loads the state into a temporary,
 *    transaction-local context (ephemeral cache). This is a cheap operation.
 * 2. batchPersist: Takes keys from the ephemeral cache and writes them permanently
 *    to the global Verkle tree. This is a more expensive, explicit action.
 * 3. decommission: Removes state from the active tree and provides a gas refund,
 *    incentivizing state cleanup.
 */
contract RevivalPrecompileV2 is ReentrancyGuard {
    using WitnessValidator for WitnessValidator.Witness[];

    // --- Events ---
    event StateRevived(address indexed caller, bytes32[] keys);
    event StatePersisted(address indexed caller, bytes32[] keys);
    event StateDecommissioned(address indexed caller, bytes32[] keys, uint256 gasRefund);

    // --- Errors ---
    error InvalidWitness();
    error InsufficientFee();
    error PersistenceFailed();
    error DecommissionFailed();
    error NothingToPersist();
    error NothingToDecommission();

    // --- Constants ---
    address public constant NATIVE_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000000A; 
    uint256 public constant BASE_REVIVAL_FEE = 2000;
    uint256 public constant PER_WITNESS_FEE = 5000;
    uint256 public constant BASE_PERSIST_FEE = 15000;
    uint256 public constant PER_KEY_PERSIST_FEE = 5000;
    uint256 public constant DECOMMISSION_REFUND_BASE = 10000;

    /**
     * @notice Revives expired state into a transaction-local ephemeral cache.
     * Verifies Verkle proofs and checks nonces to prevent replay attacks.
     * The revived state is only visible within the current transaction until persisted.
     * @param witnesses An array of proofs and nonces for the state to be revived.
     */
    function revive(WitnessValidator.Witness[] calldata witnesses)
        external
        payable
        nonReentrant(_REVIVE_LOCK)
    {
        uint256 requiredFee = BASE_REVIVAL_FEE + (witnesses.length * PER_WITNESS_FEE);
        if (msg.value < requiredFee) revert InsufficientFee();

        // 1. Validate nonces to prevent replay attacks.
        bytes32[] memory witnessHashes = WitnessValidator.validate(witnesses);
        bytes32[] memory keys = new bytes32[](witnesses.length);
        bytes[] memory proofs = new bytes[](witnesses.length);

        for (uint i = 0; i < witnesses.length; i++) {
            proofs[i] = witnesses[i].proof;
        }

        // 2. Call the native precompile to verify Verkle proofs and populate the ephemeral cache.
        (bool success, bytes memory returnData) = NATIVE_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(this.revive.selector, proofs)
        );

        if (!success) revert InvalidWitness();
        keys = abi.decode(returnData, (bytes32[]));

        emit StateRevived(msg.sender, keys);
    }

    /**
     * @notice Persists previously revived state from the ephemeral cache to the global Verkle tree.
     * This is an explicit, state-changing action with a higher gas cost.
     * @param keys The state keys to persist from the ephemeral cache.
     */
    function batchPersist(bytes32[] calldata keys)
        external
        payable
        nonReentrant(_PERSIST_LOCK)
    {
        if (keys.length == 0) revert NothingToPersist();

        uint256 requiredFee = BASE_PERSIST_FEE + (keys.length * PER_KEY_PERSIST_FEE);
        if (msg.value < requiredFee) revert InsufficientFee();

        (bool success, ) = NATIVE_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(this.batchPersist.selector, keys)
        );

        if (!success) revert PersistenceFailed();

        emit StatePersisted(msg.sender, keys);
    }

    /**
     * @notice Decommissions active state, removing it from the Verkle tree and providing a gas refund.
     * This creates an economic incentive for contracts and users to clean up obsolete state.
     * @param keys The state keys to decommission.
     */
    function decommission(bytes32[] calldata keys)
        external
        nonReentrant(_DECOMMISSION_LOCK)
    {
        if (keys.length == 0) revert NothingToDecommission();
        
        (bool success, ) = NATIVE_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(this.decommission.selector, keys)
        );

        if (!success) revert DecommissionFailed();

        uint256 gasRefund = DECOMMISSION_REFUND_BASE * keys.length;
        
        emit StateDecommissioned(msg.sender, keys, gasRefund);
    }
}
