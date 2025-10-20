// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title WitnessValidator
 * @author Technical Research Synthesis Group
 * @notice A library for handling witness validation logic, primarily nonce checking,
 * before passing data to the native Revival Precompile.
 */
library WitnessValidator {
    // Mapping from a witness hash to its last used nonce.
    mapping(bytes32 => uint256) public witnessNonces;

    struct Witness {
        bytes proof; // The serialized Verkle proof
        uint256 nonce; // The anti-replay nonce
    }

    event WitnessesValidated(uint256 count);

    /**
     * @dev Validates a batch of witnesses against their nonces.
     * @param witnesses An array of Witness structs to validate.
     * @return witnessHashes An array of the hashes of the validated witnesses.
     */
    function validate(Witness[] calldata witnesses) internal returns (bytes32[] memory) {
        uint256 len = witnesses.length;
        require(len > 0, "WitnessValidator: no witnesses provided");
        require(len <= 100, "WitnessValidator: batch size exceeds limit");

        bytes32[] memory witnessHashes = new bytes32[](len);

        for (uint256 i = 0; i < len; ) {
            bytes32 witnessHash = keccak256(witnesses[i].proof);
            uint256 nonce = witnesses[i].nonce;

            require(nonce > witnessNonces[witnessHash], "WitnessValidator: stale witness (replay)");
            
            witnessNonces[witnessHash] = nonce;
            witnessHashes[i] = witnessHash;

            unchecked {
                ++i;
            }
        }

        emit WitnessesValidated(len);
        return witnessHashes;
    }
}
