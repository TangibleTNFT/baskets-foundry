// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
/**
 * @title ERC4626 Fee-on-Transfer Router
 * @dev This contract acts as a router for interacting with ERC4626 vaults, specially designed to support
 * fee-on-transfer tokens. It handles the minting, depositing, withdrawing, and redeeming processes while accounting
 * for possible fees deducted during token transfers. This router abstracts the complexity of interacting directly with
 * ERC4626 vault contracts and manages the transfer of assets into and out of the vault, ensuring accurate handling of
 * token fees. Error handling is incorporated to revert transactions under undesirable conditions, such as insufficient
 * outputs or exceeding maximum inputs.
 *
 * Error Codes:
 * - ERC4626RouterInsufficientAmount: Indicates an attempt to redeem shares for an amount lower than the minimum
 *                                    specified.
 * - ERC4626RouterInsufficientShares: Indicates an attempt to deposit an amount resulting in fewer shares than the
 *                                    minimum specified.
 * - ERC4626RouterMaxAmountExceeded: Indicates an attempt to mint shares requiring an asset amount higher than the
 *                                   maximum allowed.
 * - ERC4626RouterMaxSharesExceeded: Indicates an attempt to withdraw an amount resulting in more shares being used than
 *                                   the maximum allowed.
 */
contract ERC4626FeeOnTransferRouter {
    using SafeERC20 for IERC20;
    error ERC4626RouterInsufficientAmount();
    error ERC4626RouterInsufficientShares();
    error ERC4626RouterMaxAmountExceeded();
    error ERC4626RouterMaxSharesExceeded();
    /**
     * @notice Mints shares in the specified ERC4626 vault and assigns them to the `to` address, accounting for any
     * potential transfer fees deducted from the tokens during the transfer process.
     *
     * @dev This function handles the asset transfer required for minting shares in the vault, ensuring the amount of
     * assets transferred does not exceed `maxAmountIn`. It accounts for fee-on-transfer tokens by using
     * `_transferInternal` to handle the actual token transfer, ensuring the correct amount is recorded post-fees. The
     * function increases the allowance for the vault to spend the adjusted asset amount, then calls `mint` on the
     * vault. If the minted amount is less than the net amount transferred (after fees), the surplus is refunded to the
     * caller.
     *
     * Requirements:
     * - The actual amount needed to mint `shares` must not exceed `maxAmountIn`.
     * - The caller must have a sufficient balance and have given the router contract enough allowance to transfer the
     *   required asset amount.
     *
     * @param vault The address of the ERC4626 vault where shares are to be minted.
     * @param to The address to which the minted shares will be assigned.
     * @param shares The amount of shares to mint in the vault.
     * @param maxAmountIn The maximum amount of the vault's underlying asset that the caller is willing to spend on
     *                    minting.
     * @return amountIn The actual amount of the vault's underlying asset used to mint the specified `shares`, adjusted
     * for any fees.
     */
    function mint(IERC4626 vault, address to, uint256 shares, uint256 maxAmountIn)
        external
        returns (uint256 amountIn)
    {
        amountIn = vault.previewMint(shares);
        if (amountIn > maxAmountIn) {
            revert ERC4626RouterMaxAmountExceeded();
        }
        IERC20 asset = IERC20(vault.asset());
        amountIn = _transferInternal(asset, msg.sender, address(this), amountIn);
        asset.forceApprove(address(vault), amountIn);
        uint256 amount = vault.mint(shares, to);
        if (amount < amountIn) {
            asset.forceApprove(address(vault), 0);
            unchecked {
                asset.safeTransfer(msg.sender, amountIn - amount);
            }
        }
    }
    /**
     * @notice Deposits the specified amount of the vault's underlying asset into the vault in exchange for vault
     * shares, assigned to the `to` address, with consideration for fee-on-transfer tokens.
     *
     * @dev This function facilitates the deposit of assets into the specified ERC4626 vault, converting the deposited
     * assets into vault shares. It accounts for fee-on-transfer tokens by using `_transferInternal` to handle the
     * actual token transfer, ensuring the correct amount is recorded post-fees.
     * The function then increases the allowance for the vault to spend these adjusted assets and proceeds to deposit
     * the assets into the vault, which in turn mints the shares directly to the `to` address.
     * If the actual shares minted are less than `minSharesOut`, the operation is reverted to prevent a less favorable
     * exchange rate.
     *
     * Requirements:
     * - The deposit must result in at least `minSharesOut` shares being minted to the `to` address.
     * - The caller must have a sufficient balance and have granted the router contract enough allowance to transfer the
     *   specified amount of the asset.
     *
     * @param vault The address of the ERC4626 vault where the assets are to be deposited.
     * @param to The address that will receive the shares from the deposit.
     * @param amount The amount of the vault's underlying asset to be deposited.
     * @param minSharesOut The minimum number of shares the depositor expects to receive for their deposit.
     * @return sharesOut The actual number of shares minted to the `to` address as a result of the deposit, adjusted for
     * any fees.
     */
    function deposit(IERC4626 vault, address to, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 sharesOut)
    {
        sharesOut = vault.previewDeposit(amount);
        if (sharesOut < minSharesOut) {
            revert ERC4626RouterInsufficientShares();
        }
        IERC20 asset = IERC20(vault.asset());
        amount = _transferInternal(asset, msg.sender, address(this), amount);
        asset.forceApprove(address(vault), amount);
        uint256 shares = vault.deposit(amount, to);
        if (shares < minSharesOut) {
            revert ERC4626RouterInsufficientShares();
        }
    }
    /**
     * @notice Withdraws a specified amount of the vault's underlying asset from the vault, using the caller's shares,
     * and sends the assets to the `to` address, accounting for fee-on-transfer tokens.
     *
     * @dev This function facilitates the withdrawal of assets from the specified ERC4626 vault in exchange for burning
     * a portion of the caller's shares in the vault. It directly calls the vault's `withdraw` function, which also
     * performs the actual withdrawal and share burning. If the number of shares required exceeds `maxSharesOut`, the
     * transaction is reverted to prevent the use of more shares than the caller is willing to spend.
     * This function ensures that the caller does not inadvertently spend more shares than intended for the withdrawal
     * amount, especially important when dealing with fee-on-transfer tokens that might alter the amount of assets
     * received.
     *
     * Requirements:
     * - The withdrawal must not require more than `maxSharesOut` shares to be burned.
     * - The caller must have enough shares in the vault to cover the withdrawal and have granted the router contract
     *   enough allowance to transfer the specified amount of the asset.
     *
     * @param vault The address of the ERC4626 vault from which the assets are to be withdrawn.
     * @param to The address that will receive the withdrawn assets.
     * @param amount The amount of the vault's underlying asset to withdraw.
     * @param maxSharesOut The maximum number of shares the caller is willing to spend to perform the withdrawal.
     * @return sharesOut The actual number of shares burned in exchange for the withdrawn assets.
     */
    function withdraw(IERC4626 vault, address to, uint256 amount, uint256 maxSharesOut)
        external
        returns (uint256 sharesOut)
    {
        sharesOut = vault.withdraw(amount, to, msg.sender);
        if (sharesOut > maxSharesOut) {
            revert ERC4626RouterMaxSharesExceeded();
        }
    }
    /**
     * @notice Redeems a specified number of shares from the vault for its underlying asset, sending the asset to the
     * `to` address, and deducting the shares from the caller's balance, with special handling for fee-on-transfer
     * tokens.
     *
     * @dev This function allows the caller to exchange their shares in the vault for the underlying assets. The
     * function computes the amount of underlying asset equivalent to the specified number of shares and performs the
     * redemption.
     * If the resulting amount of assets is less than `minAmountOut`, the operation is reverted to ensure that the
     * redemption does not result in receiving less than the expected amount of the underlying asset, taking into
     * account the characteristics of fee-on-transfer tokens.
     *
     * Requirements:
     * - The redemption must result in the caller receiving at least `minAmountOut` of the underlying asset.
     * - The caller must have enough shares to cover the redemption.
     *
     * @param vault The address of the ERC4626 vault from which the shares are to be redeemed.
     * @param to The address that will receive the redeemed assets.
     * @param shares The number of shares to redeem from the vault.
     * @param minAmountOut The minimum amount of the vault's underlying asset the redeemer expects to receive.
     * @return amountOut The actual amount of the underlying asset received as a result of the redemption.
     */
    function redeem(IERC4626 vault, address to, uint256 shares, uint256 minAmountOut)
        external
        returns (uint256 amountOut)
    {
        amountOut = vault.redeem(shares, to, msg.sender);
        if (amountOut < minAmountOut) {
            revert ERC4626RouterInsufficientAmount();
        }
    }
    /**
     * @notice Internally handles the transfer of tokens, accounting for possible discrepancies in balance due to fees.
     * @dev Transfers `amount` of `token` from `from` to `to`, automatically adjusting for any fees by checking the
     * balance change. This is critical for handling fee-on-transfer tokens where the actual amount transferred may be
     * less than the requested.
     *
     * @param token The token being transferred.
     * @param from The address from which the token is being transferred.
     * @param to The address to which the token is being transferred.
     * @param amount The nominal amount of the token to transfer.
     * @return The actual amount of tokens that were added to the `to` address's balance, reflecting any transfer fees
     * deducted.
     */
    function _transferInternal(IERC20 token, address from, address to, uint256 amount) internal returns (uint256) {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        return token.balanceOf(to) - balanceBefore;
    }
}