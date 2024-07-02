// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { OFTCoreUpgradeable, OFTUpgradeable } from "@tangible-foundation-contracts/layerzero/token/oft/v1/OFTUpgradeable.sol";
import { IOFTCore } from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";

import { IRebaseToken } from "../interfaces/IRebaseToken.sol";

/**
 * @title WrappedBasketToken
 * @notice Wrapped basket token using ERC-4626 for "unwrapping" and "wrapping" basket tokens in this vault contract.
 * This contract also utilizes OFTUpgradeable for cross chain functionality to optimize the baskets footprint.
 */
contract WrappedBasketToken is UUPSUpgradeable, OFTUpgradeable, IERC4626 {

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
        __OFT_init(owner, name, symbol);
    }


    // ~ Methods ~

    /**
     * @notice Returns the amount of assets this contract has minted.
     */
    function totalAssets() external view override returns (uint256) {
        return _convertToAssetsDown(totalSupply());
    }

    /**
     * @notice Converts assets to shares.
     * @dev "shares" is the variable balance/totalSupply that is NOT affected by an index.
     * @param assets Num of assets to convert to shares.
     */
    function convertToShares(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesDown(assets);
    }

    /**
     * @notice Converts shares to assets.
     * @dev "assets" is the variable balance/totalSupply that IS affected by an index.
     * @param shares Num of shares to convert to assets.
     */
    function convertToAssets(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(shares);
    }

    /**
     * @notice The maximum amount that is allowed to be deposited at one time.
     */
    function maxDeposit(
        address /*receiver*/
    ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Takes assets and returns a preview of the amount of shares that would be received
     * if the amount assets was deposited via `deposit`.
     */
    function previewDeposit(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesDown(assets);
    }

    /**
     * @notice Allows a user to deposit assets amount of `asset` into this contract to receive
     * shares amount of wrapped basket token.
     * @dev I.e. Deposit X UKRE to get Y wUKRE: X is provided
     * @param assets Amount of asset.
     * @param receiver Address that will be minted wrappd token.
     */
    function deposit(uint256 assets, address receiver)
        external
        override
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

    /**
     * @notice Maximum amount allowed to be minted at once.
     */
    function maxMint(
        address /*receiver*/
    ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Takes shares amount and returns the amount of base token that would be
     * required to mint that many shares of wrapped token.
     */
    function previewMint(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsUp(shares);
    }

    /**
     * @notice Allows a user to mint shares amount of wrapped token.
     * @dev I.e. Mint X wUKRE using Y UKRE: X is provided
     * @param shares Amount of wrapped token the user desired to mint.
     * @param receiver Address where the wrapped token will be minted to.
     */
    function mint(uint256 shares, address receiver)
        external
        override
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

    /**
     * @notice Maximum amount of basket tokens allowed to be withdrawn for `owner`.
     * It will check the `owner` balance of wrapped tokens to quote withdraw.
     */
    function maxWithdraw(address owner)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(balanceOf(owner));
    }

    /**
     * @notice Returns the amount of wrapped basket tokens that would be required if
     * `assets` amount of basket tokens was withdrawn from this contract.
     */
    function previewWithdraw(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesUp(assets);
    }

    /**
     * @notice Allows a user to withdraw a specified amount of basket tokens from contract.
     * @dev I.e. Withdraw X UKRE from Y wUKRE: X is provided
     * @param assets Amount of basket tokens the user desired to withdraw.
     * @param receiver Address where the basket tokens are transferred to.
     * @param owner Current owner of wrapped basket tokens.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override returns (uint256 shares) {
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

    /**
     * @notice Maximum amount of wrapped basket tokens an `owner` can use to redeem basket tokens.
     */
    function maxRedeem(address owner) external view override returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @notice Returns an amount of basket tokens that would be redeemed if `shares` amount of wrapped tokens
     * were used to redeem.
     */
    function previewRedeem(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(shares);
    }

    /**
     * @notice Allows a user to use a specified amount of wrapped basket tokens to redeem basket tokens.
     * @dev I.e. Redeem X wUKRE for Y UKRE: X is provided
     * @param shares Amount of wrapped basket tokens the user wants to use in order to redeem basket tokens.
     * @param receiver Address where the basket tokens are transferred to.
     * @param owner Current owner of wrapped basket tokens. shares` amount will be burned from this address.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override returns (uint256 assets) {
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


    // ~ Internal Methods ~

    /**
     * @dev Returns the rebase index of the underlying asset token.
     */
    function _getRate() private view returns (uint256) {
        return IRebaseToken(asset).rebaseIndex();
    }

    /**
     * @dev Converts assets to shares, rounding up.
     */
    function _convertToSharesUp(uint256 assets) private view returns (uint256) {
        uint256 rate = _getRate();
        return (rate / 2 + assets * WAD) / rate;
    }

    /**
     * @dev Converts shares to assets, rounding up.
     */
    function _convertToAssetsUp(uint256 shares) private view returns (uint256) {
        return (HALF_WAD + shares * _getRate()) / WAD;
    }

    /**
     * @dev Converts assets to shares, rounding down.
     */
    function _convertToSharesDown(uint256 assets)
        private
        view
        returns (uint256)
    {
        return (assets * 10**decimals()) / _getRate();
    }

    /**
     * @dev Converts shares to assets, rounding down.
     */
    function _convertToAssetsDown(uint256 shares)
        private
        view
        returns (uint256)
    {
        return (shares * _getRate()) / 10**decimals();
    }

    /**
     * @dev Pulls assets from `from` address of `amount`. Performs a pre and post balance check to 
     * confirm the amount received, and returns that amount.
     */
    function _pullAssets(address from, uint256 amount) private returns (uint256 received) {
        uint256 preBal = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transferFrom(from, address(this), amount);
        received = IERC20(asset).balanceOf(address(this)) - preBal;
    }

    /**
     * @dev Transfers an `amount` of `asset` to the `to` address.
     */
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
    ) public payable override(IOFTCore, OFTCoreUpgradeable) {
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