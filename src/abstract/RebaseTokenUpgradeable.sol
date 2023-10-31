// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { RebaseTokenMath } from "../libraries/RebaseTokenMath.sol";

/**
 * @title RebaseTokenUpgradeable
 * @author Caesar LaVey - slight variation configured by Chase Brown
 * @notice This is an upgradeable ERC20 token contract that introduces a rebase mechanism and allows accounts to opt out
 * of rebasing. The contract uses an multiplier-based approach to implement rebasing, allowing for more gas-efficient
 * calculations.
 *
 * @dev The contract inherits from OpenZeppelin's ERC20Upgradeable and utilizes the RebaseTokenMath library for its
 * arithmetic operations. It introduces a new struct "RebaseTokenStorage" to manage its state. The state variables
 * include `multiplier`, which is the current multiplier value for rebasing, and `totalShares`, which is the total number of
 * multiplier-based shares in circulation.
 *
 * The contract makes use of low-level Solidity features like assembly for optimized storage handling. It adheres to the
 * Checks-Effects-Interactions design pattern where applicable and emits events for significant state changes.
 */
abstract contract RebaseTokenUpgradeable is ERC20Upgradeable {
    using RebaseTokenMath for uint256;

    /// @custom:storage-location erc7201:tangible.storage.RebaseToken
    struct RebaseTokenStorage {
        uint256 multiplier;
        uint256 totalShares; // Note: shares refers to tokens + rebase tokens
        mapping(address => uint256) shares;
    }

    // keccak256(abi.encode(uint256(keccak256("tangible.storage.RebaseToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RebaseTokenStorageLocation =
        0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;

    function _getRebaseTokenStorage() private pure returns (RebaseTokenStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := RebaseTokenStorageLocation
        }
    }

    event MultiplierUpdated(address updatedBy, uint256 multiplier);

    error AmountExceedsBalance(address account, uint256 balance, uint256 amount);

    /**
     * @notice Initializes the RebaseTokenUpgradeable contract.
     * @dev This function should only be called once during the contract deployment. It internally calls
     * `__RebaseToken_init_unchained` for any further initializations and `__ERC20_init` to initialize the inherited
     * ERC20 contract.
     *
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function __RebaseToken_init(string memory name, string memory symbol) internal onlyInitializing {
        __RebaseToken_init_unchained();
        __ERC20_init(name, symbol);
    }

    function __RebaseToken_init_unchained() internal onlyInitializing {}

    /**
     * @notice Returns the current rebase multiplier of the token.
     * @dev This function fetches the `multiplier` from the contract's storage and returns it. The returned multiplier is
     * used in various calculations related to token rebasing.
     *
     * @return multiplier The current rebase multiplier.
     */
    function multiplier() public view returns (uint256 multiplier) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        multiplier = $.multiplier;
    }

    /**
     * @notice Returns the balance of a specific account, adjusted for the current rebase multiplier.
     * @dev This function fetches the `shares` and `multiplier` from the contract's storage for the specified account.
     * It then calculates the balance in tokens by converting these shares to their equivalent token amount using the
     * current rebase multiplier.
     *
     * @param account The address of the account whose balance is to be fetched.
     * @return balance The balance of the specified account in tokens.
     */
    function balanceOf(address account) public view virtual override returns (uint256 balance) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        balance = $.shares[account].toTokens($.multiplier);
    }

    /**
     * @notice Returns the total supply of the token, taking into account the current rebase multiplier.
     * @dev This function fetches the `totalShares` and `multiplier` from the contract's storage. It then calculates
     * the total supply of tokens by converting these shares to their equivalent token amount using the current rebase
     * multiplier.
     *
     * @return supply The total supply of tokens.
     */
    function totalSupply() public view virtual override returns (uint256 supply) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        supply = $.totalShares.toTokens($.multiplier) + ERC20Upgradeable.totalSupply();
    }

    /**
     * @notice Sets a new rebase multiplier for the token.
     * @dev This function updates the `multiplier` state variable if the new multiplier differs from the current one. It
     * also performs a check for any potential overflow conditions that could occur with the new multiplier. Emits a
     * `MultiplierUpdated` event upon successful update.
     *
     * @param multiplier The new rebase multiplier to set.
     */
    function _setMultiplier(uint256 multiplier) internal virtual {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        if ($.multiplier != multiplier) {
            $.multiplier = multiplier;
            _checkRebaseOverflow($.totalShares, multiplier);
            emit MultiplierUpdated(msg.sender, multiplier);
        }
    }

    /**
     * @notice Calculates the number of transferable shares for a given amount and account.
     * @dev This function fetches the current rebase multiplier and the shares held by the `from` address. It then converts
     * these shares to the equivalent token balance. If the `amount` to be transferred exceeds this balance, the
     * function reverts with an `AmountExceedsBalance` error. Otherwise, it calculates the number of shares equivalent
     * to the `amount` to be transferred.
     *
     * @param amount The amount of tokens to be transferred.
     * @param from The address from which the tokens are to be transferred.
     * @return shares The number of shares equivalent to the `amount` to be transferred.
     */
    function _transferableShares(uint256 amount, address from) internal view returns (uint256 shares) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        shares = $.shares[from];
        uint256 multiplier = $.multiplier;
        uint256 balance = shares.toTokens(multiplier);
        if (amount > balance) {
            revert AmountExceedsBalance(from, balance, amount);
        }
        if (amount < balance) {
            shares = amount.toShares(multiplier);
        }
    }

    /**
     * @notice Updates the state of the contract during token transfers, mints, or burns.
     * @dev This function adjusts the `totalShares` and individual `shares` of `from` and `to` addresses.
     * It performs overflow and underflow checks where necessary.
     *
     * @param from The address from which tokens are transferred or burned. Address(0) implies minting.
     * @param to The address to which tokens are transferred or minted. Address(0) implies burning.
     * @param amount The amount of tokens to be transferred.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        uint256 multiplier = $.multiplier;
        uint256 shares = amount.toShares($.multiplier);
        if (from == address(0)) {
            uint256 totalShares = $.totalShares + shares; // Overflow check required
            _checkRebaseOverflow(totalShares, multiplier);
            $.totalShares = totalShares;
        } else {
            shares = _transferableShares(amount, from);
            unchecked {
                // Underflow not possible: `shares <= $.shares[from] <= totalShares`.
                $.shares[from] -= shares;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Underflow not possible: `shares <= $.totalShares` or `shares <= $.shares[from] <= $.totalShares`.
                $.totalShares -= shares;
            }
        } else {
            unchecked {
                // Overflow not possible: `$.shares[to] + shares` is at most `$.totalShares`, which we know fits into a
                // `uint256`.
                $.shares[to] += shares;
            }
        }

        emit Transfer(from, to, amount);
    }

    /**
     * @notice Checks for potential overflow conditions in token-to-share calculations.
     * @dev This function uses an `assert` statement to ensure that converting shares to tokens using the provided
     * `multiplier` will not result in an overflow. It leverages the `toTokens` function from the `RebaseTokenMath` library
     * to perform this check.
     *
     * @param shares The number of shares involved in the operation.
     * @param multiplier The current rebase multiplier.
     */
    function _checkRebaseOverflow(uint256 shares, uint256 multiplier) private view {
        // The condition inside `assert()` can never evaluate `false`, but `toTokens()` would throw an arithmetic
        // exception in case we overflow, and that's all we need.
        assert(shares.toTokens(multiplier) + ERC20Upgradeable.totalSupply() <= type(uint256).max);
    }
}