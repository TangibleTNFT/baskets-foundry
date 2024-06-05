// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { ERC20Upgradeable, OFTCoreUpgradeable, OFTUpgradeable } from "@tangible-foundation-contracts/layerzero/token/oft/v1/OFTUpgradeable.sol";
import { IOFTCore } from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";

import { IRebaseToken } from "../interfaces/IRebaseToken.sol";

/**
 * @title WrappedBasketTokenSatellite
 * @notice Wrapped basket token using ERC-4626 for "unwrapping" and "wrapping" basket tokens in this vault contract.
 * This contract also utilizes OFTUpgradeable for cross chain functionality to optimize the baskets footprint.
 */
contract WrappedBasketTokenSatellite is UUPSUpgradeable, PausableUpgradeable, OFTUpgradeable {
    // ~ Constructor ~

    /**
     * @notice Initializes WrappedBasketTokenSatellite.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     */
    constructor(address lzEndpoint) OFTUpgradeable(lzEndpoint) {}


    // ~ Initializer ~

    /**
     * @notice Initializes WrappedBasketTokenSatellite's inherited upgradeables.
     * @param owner Initial owner of contract.
     * @param name Name of wrapped token.
     * @param symbol Symbol of wrapped token.
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol
    ) external initializer {
        __Ownable_init(owner);
        __Pausable_init();
        __OFT_init(owner, name, symbol);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // ~ LayerZero overrides ~

    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes calldata _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) public payable override(IOFTCore, OFTCoreUpgradeable) whenNotPaused {
        _send(
            _from,
            _dstChainId,
            _toAddress,
            _amount,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }
}