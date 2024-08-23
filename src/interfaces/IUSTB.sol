// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUSTB {
    event RebaseIndexManagerUpdated(address manager);

    error InvalidZeroAddress();
    error NotAuthorized(address caller);
    error UnsupportedChain(uint256 chainId);
    error ValueUnchanged();

    /**
     * Returns the underlying address.
     */
    function UNDERLYING() external view returns (address);

    /**
     * @notice Initializes the USTB contract with essential parameters.
     * @dev This function sets the initial LayerZero endpoint and the rebase index manager. It also calls
     * `__LayerZeroRebaseToken_init` for further initialization.
     *
     * @param indexManager The address that will manage the rebase index.
     */
    function initialize(address indexManager) external;

    /**
     * @notice Burns a specified amount of USTB tokens from a given address.
     * @dev This function first burns the specified amount of USTB tokens from the target address. Then, it transfers
     * the equivalent amount of the underlying asset back to the caller. The function can only be called if the contract
     * is on the main chain. It also updates the rebase index before burning.
     *
     * @param from The address from which the tokens will be burned.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Mints a specified amount of USTB tokens to a given address.
     * @dev This function first transfers the underlying asset from the caller to the contract. Then, it mints the
     * equivalent amount of USTB tokens to the target address. The function can only be called if the contract is on the
     * main chain. It also updates the rebase index before minting.
     *
     * @param to The address to which the tokens will be minted.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Enables or disables rebasing for a specific account.
     * @dev This function can be called by either the account itself or the rebase index manager.
     *
     * @param account The address of the account for which rebasing is to be enabled or disabled.
     * @param disable A boolean flag indicating whether to disable (true) or enable (false) rebasing for the account.
     */
    function disableRebase(address account, bool disable) external;

    /**
     * @notice Sets the rebase index and its corresponding nonce on non-main chains.
     * @dev This function allows the rebase index manager to manually update the rebase index and nonce when not on the
     * main chain. The main chain manages the rebase index automatically within `refreshRebaseIndex`. It should only be
     * used on non-main chains to align them with the main chain's state.
     *
     * Reverts if called on the main chain due to the `mainChain(false)` modifier.
     *
     * @param index The new rebase index to set.
     * @param nonce The new nonce corresponding to the rebase index.
     */
    function setRebaseIndex(uint256 index, uint256 nonce) external;

    /**
     * @notice Returns the address of rebase index manager.
     */
    function rebaseIndexManager() external view returns (address _rebaseIndexManager);

    /**
     * @notice Updates the rebase index to the current index from the underlying asset on the main chain.
     * @dev Automatically refreshes the rebase index by querying the current reward multiplier from the underlying asset
     * contract. This can only affect the rebase index on the main chain. If the current index from the underlying
     * differs from the stored rebase index, it updates the rebase index and sets the current block number as the nonce.
     *
     * This function does not have effect on non-main chains as their rebase index and nonce are managed through
     * `setRebaseIndex`.
     */
    function refreshRebaseIndex() external;

    /**
     * @notice Sets the address of the rebase index manager.
     * @dev This function allows the contract owner to change the rebase index manager, who has the permission to update
     * the rebase index.
     *
     * @param manager The new rebase index manager address.
     */
    function setRebaseIndexManager(address manager) external;

    function optedOut(address account) external view returns (bool);
}
