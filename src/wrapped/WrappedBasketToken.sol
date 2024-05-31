// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626, IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { ERC20Upgradeable, OFTCoreUpgradeable, OFTUpgradeable } from "@tangible-foundation-contracts/layerzero/token/oft/v1/OFTUpgradeable.sol";
import { IOFTCore } from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";

import { IRebaseToken } from "../interfaces/IRebaseToken.sol";

/**
 * @title WrappedBasketToken
 * @notice Wrapped basket token using ERC-4626 for "unwrapping" and "wrapping" basket tokens in this vault contract.
 * This contract also utilizes OFTUpgradeable for cross chain functionality to optimize the baskets footprint.
 */
contract WrappedBasketToken is UUPSUpgradeable, PausableUpgradeable, OFTUpgradeable, IERC4626 {

    // ~ State Variables ~

    /// @notice Address of basket token being "wrapped".
    address public immutable asset;
    /// @notice Half of WAD. Used for conversions.
    uint256 internal constant HALF_WAD = 5e17;
    /// @notice WAD constant uses for conversions.
    uint256 internal constant WAD = 1e18;


    // ~ Events ~

    /// @notice This event is fired if this contract is opted out of `asset` rebase.
    event RebaseDisabled(address indexed asset);


    // ~ Constructor ~

    /**
     * @notice Initializes WrappedBasketToken.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     * @param basketToken Will be assigned to `asset`.
     */
    constructor(address lzEndpoint, address basketToken) OFTUpgradeable(lzEndpoint) {
        (bool success,) = basketToken.call(abi.encodeCall(IRebaseToken.disableRebase, (address(this), true)));
        if (success) {
            emit RebaseDisabled(basketToken);
        }
        asset = basketToken;
    }


    // ~ Initializer ~

    /**
     * @notice Initializes WrappedBasketToken's inherited upgradeables.
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


    // ~ Methods ~

    function totalAssets() external view override returns (uint256) {
        return _convertToAssetsDown(totalSupply());
    }

    function convertToShares(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesDown(assets);
    }

    function convertToAssets(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(shares);
    }

    function maxDeposit(
        address /*receiver*/
    ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesDown(assets);
    }

    function deposit(uint256 assets, address receiver)
        external
        override
        whenNotPaused
        returns (uint256 shares)
    {
        require(
            receiver != address(0),
            "Zero address for receiver not allowed"
        );

        uint256 amountReceived = _pullAssets(msg.sender, assets);
        shares = _convertToSharesDown(amountReceived);

        if (shares != 0) {
            _mint(receiver, shares);
        }

        emit Deposit(msg.sender, receiver, amountReceived, shares);
    }

    function maxMint(
        address /*receiver*/
    ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsUp(shares);
    }

    function mint(uint256 shares, address receiver)
        external
        override
        whenNotPaused
        returns (uint256 assets)
    {
        require(
            receiver != address(0),
            "Zero address for receiver not allowed"
        );

        assets = _convertToAssetsUp(shares);

        uint256 amountReceived;
        if (assets != 0) {
            amountReceived = _pullAssets(msg.sender, assets);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amountReceived, shares);
    }

    function maxWithdraw(address owner)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(balanceOf(owner));
    }

    function previewWithdraw(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesUp(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override whenNotPaused returns (uint256 shares) {
        require(
            receiver != address(0),
            "Zero address for receiver not allowed"
        );
        require(owner != address(0), "Zero address for owner not allowed");

        shares = _convertToSharesUp(assets);

        if (owner != msg.sender) {
            uint256 currentAllowance = allowance(owner, msg.sender);
            require(
                currentAllowance >= shares,
                "Withdraw amount exceeds allowance"
            );
            _approve(owner, msg.sender, currentAllowance - shares);
        }

        if (shares != 0) {
            _burn(owner, shares);
        }

        _pushAssets(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        return balanceOf(owner);
    }

    function previewRedeem(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override whenNotPaused returns (uint256 assets) {
        require(
            receiver != address(0),
            "Zero address for receiver not allowed"
        );
        require(owner != address(0), "Zero address for owner not allowed");

        if (owner != msg.sender) {
            uint256 currentAllowance = allowance(owner, msg.sender);
            require(
                currentAllowance >= shares,
                "Redeem amount exceeds allowance"
            );
            _approve(owner, msg.sender, currentAllowance - shares);
        }

        _burn(owner, shares);

        assets = _convertToAssetsDown(shares);

        if (assets != 0) {
            _pushAssets(receiver, assets);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function _getRate() private view returns (uint256) {
        return IRebaseToken(asset).rebaseIndex();
    }

    function _convertToSharesUp(uint256 assets) private view returns (uint256) {
        uint256 rate = _getRate();
        return (rate / 2 + assets * WAD) / rate;
    }

    function _convertToAssetsUp(uint256 shares) private view returns (uint256) {
        return (HALF_WAD + shares * _getRate()) / WAD;
    }

    function _convertToSharesDown(uint256 assets)
        private
        view
        returns (uint256)
    {
        return (assets * 10**decimals()) / _getRate();
    }

    function _convertToAssetsDown(uint256 shares)
        private
        view
        returns (uint256)
    {
        return (shares * _getRate()) / 10**decimals();
    }

    function _pullAssets(address from, uint256 amount) private returns (uint256 received) {
        uint256 preBal = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transferFrom(from, address(this), amount);
        received = IERC20(asset).balanceOf(address(this)) - preBal;
    }

    function _pushAssets(address to, uint256 amount) private {
        IERC20(asset).transfer(to, amount);
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

    function _debitFrom(
        address _from,
        uint16,
        bytes memory,
        uint256 _amount
    ) internal override returns (uint256) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _transfer(_from, address(this), _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _amount
    ) internal override returns (uint256) {
        _transfer(address(this), _toAddress, _amount);
        return _amount;
    }
}