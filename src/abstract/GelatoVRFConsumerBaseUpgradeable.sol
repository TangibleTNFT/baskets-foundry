// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IGelatoVRFConsumer } from "@vrf/contracts/IGelatoVRFConsumer.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title GelatoVRFConsumerBaseUpgradeable
/// @dev This contract handles domain separation between consecutive randomness requests
/// The contract has to be implemented by contracts willing to use the gelato VRF system.
/// This base contract enhances the GelatoVRFConsumer by introducing request IDs and
/// ensuring unique random values.
/// for different request IDs by hashing them with the random number provided by drand.
/// For security considerations, refer to the Gelato documentation.
/// @dev This contract has been refactored to use EIP-7201 Namespaced storage to mitigate storage
/// clashes when being inherited by upgradeable contracts.
abstract contract GelatoVRFConsumerBaseUpgradeable is IGelatoVRFConsumer, Initializable {

    uint256 private constant _PERIOD = 3;
    uint256 private constant _GENESIS = 1692803367;

    /// @custom:storage-location erc7201:gelato.storage.GelatoVRFConsumerBaseUpgradeable
    struct GelatoVRFConsumerBaseStorage {
        bool[] requestPending;
        mapping(uint256 => bytes32) requestedHash;
        mapping(uint256 => bytes) rawRequestedHash;
        uint256 testnetChainId;
    }

    // keccak256(abi.encode(uint256(keccak256("gelato.storage.GelatoVRFConsumerBaseUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GelatoVRFConsumerBaseLocation =
        0x1260878f6c55622bb929f0462f53ee8c876708fc1d84ec7bd52a89c4c1a67800;

    function _getGelatoVRFConsumerBaseStorage() private pure returns (GelatoVRFConsumerBaseStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := GelatoVRFConsumerBaseLocation
        }
    }

    /// @notice Initializes the GelatoVRFConsumerBaseUpgradeable contract.
    /// @dev This function should only be called once during the contract deployment. It internally calls
    /// `__GelatoVRFConsumerBase_init_unchained` and sets `testnetChainId`.
    /// @param _testnetChainId testnet chain Id. Allows us to force fulfill requests on testnet.
    function __GelatoVRFConsumerBase_init(uint256 _testnetChainId) internal onlyInitializing {
        __GelatoVRFConsumerBase_init_unchained(_testnetChainId);
    }

    function __GelatoVRFConsumerBase_init_unchained(uint256 _testnetChainId) internal onlyInitializing {
        GelatoVRFConsumerBaseStorage storage $ = _getGelatoVRFConsumerBaseStorage();
        $.testnetChainId = _testnetChainId;
    }

    /// @notice Requests randomness from the Gelato VRF.
    /// @dev The extraData parameter allows for additional data to be passed to
    /// the VRF, which is then forwarded to the callback. This is useful for
    /// request tracking purposes if requestId is not enough.
    /// @param extraData Additional data for the randomness request.
    /// @return requestId The ID for the randomness request.
    function _requestRandomness(
        bytes memory extraData
    ) internal returns (uint256 requestId) {
        GelatoVRFConsumerBaseStorage storage $ = _getGelatoVRFConsumerBaseStorage();

        requestId = uint256($.requestPending.length);
        $.requestPending.push();
        $.requestPending[requestId] = true;

        bytes memory data = abi.encode(requestId, extraData);
        uint256 round = _round();

        bytes memory dataWithRound = abi.encode(round, data);
        bytes32 requestHash = keccak256(dataWithRound);

        $.requestedHash[requestId] = requestHash;
        $.rawRequestedHash[requestId] = dataWithRound;

        emit RequestedRandomness(round, data);
    }

    /// @notice Testnet Method to make manually fulfill vrf callbacks without using a vrf coordinator.
    /// @param randomness The random number generated by Gelato VRF.
    /// @param requestId The ID for the randomness request that's being fulfilled.
    function fulfillRandomnessTestnet(
        uint256 randomness,
        uint256 requestId
    ) external {
        GelatoVRFConsumerBaseStorage storage $ = _getGelatoVRFConsumerBaseStorage();
        require(block.chainid == $.testnetChainId, "Method only accessible on testnet");

        bytes storage dataWithRound = $.rawRequestedHash[requestId];
        _fulfillLogic(randomness, dataWithRound);
    }

    /// @notice Callback function used by Gelato VRF to return the random number.
    /// The randomness is derived by hashing the provided randomness with the request ID.
    /// @param randomness The random number generated by Gelato VRF.
    /// @param dataWithRound Additional data provided by Gelato VRF containing request details.
    function fulfillRandomness(
        uint256 randomness,
        bytes calldata dataWithRound
    ) external {
        require(msg.sender == _operator(), "only operator");
        _fulfillLogic(randomness, dataWithRound);
    }

    /// @notice Returns the testnetChainId variable stored in this contract.
    function testnetChainId() external view returns (uint256) {
        return _getGelatoVRFConsumerBaseStorage().testnetChainId;
    }

    /// @notice Returns the boolean value of a specific index in the `requestPending` array.
    /// @param index Index in array we wish to fetch the value of.
    function requestPending(uint256 index) external view returns (bool) {
        return _getGelatoVRFConsumerBaseStorage().requestPending[index];
    }

    /// @notice Returns the `requestPending` array in it's entirety.
    function getRequestPendingArray() external view returns (bool[] memory) {
        return _getGelatoVRFConsumerBaseStorage().requestPending;
    }

    /// @notice Returns the bytes32 value stored in the `requestedHash` mapping, given a key.
    /// @param requestId Key for fetching mapped bytes32 hash value.
    function requestedHash(uint256 requestId) external view returns (bytes32) {
        return _getGelatoVRFConsumerBaseStorage().requestedHash[requestId];
    }

    /// @notice Internal method for handling the fulfillemt of VRF requests.
    /// @param randomness The random number generated by Gelato VRF.
    /// @param dataWithRound Additional data provided by Gelato VRF containing request details.
    function _fulfillLogic(uint256 randomness, bytes memory dataWithRound) internal {
        (, bytes memory data) = abi.decode(dataWithRound, (uint256, bytes));
        (uint256 requestId, bytes memory extraData) = abi.decode(
            data,
            (uint256, bytes)
        );

        GelatoVRFConsumerBaseStorage storage $ = _getGelatoVRFConsumerBaseStorage();

        bytes32 requestHash = keccak256(dataWithRound);
        bool isValidRequestHash = requestHash == $.requestedHash[requestId];

        require($.requestPending[requestId], "request fulfilled or missing");

        if (isValidRequestHash) {
            randomness = uint(
                keccak256(
                    abi.encode(
                        randomness,
                        address(this),
                        block.chainid,
                        requestId
                    )
                )
            );

            $.requestPending[requestId] = false;
            _fulfillRandomness(randomness, requestId, extraData);
        }
    }

    /// @notice Computes and returns the round number of drand to request randomness from.
    function _round() private view returns (uint256 round) {
        // solhint-disable-next-line not-rely-on-time
        uint256 elapsedFromGenesis = block.timestamp - _GENESIS;
        uint256 currentRound = (elapsedFromGenesis / _PERIOD) + 1;

        round = block.chainid == 1 ? currentRound + 4 : currentRound + 1;
    }

    /// @notice Returns the address of the dedicated msg.sender.
    /// @dev The operator can be found on the Gelato dashboard after a VRF is deployed.
    /// @return Address of the operator.
    function _operator() internal view virtual returns (address);

    /// @notice User logic to handle the random value received.
    /// @param randomness The random number generated by Gelato VRF.
    /// @param requestId The ID for the randomness request.
    /// @param extraData Additional data from the randomness request.
    function _fulfillRandomness(
        uint256 randomness,
        uint256 requestId,
        bytes memory extraData
    ) internal virtual;
}
