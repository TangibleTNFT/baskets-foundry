// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

// TODO: Can users deposit an NFT from ANY TangibleNFT contract as long as it's of the same type/feature?
// TODO: Transfer fees?
// TODO: Liquidity backed?
// TODO: How to handle rent?
// TODO: How to handle rev shares?
// TODO: Would the deployer go in the factory?

/**
 * @title Basket
 * @author TangibleStore
 * @notice ERC-20 token that represents a basket of ERC-721 TangibleNFTs that are categorized into "baskets".
 */
contract Basket is ERC20 {

    // ~ State Variables ~

    uint256[] private depositedTokenIds;

    /// @notice TangibleNFT contract => tokenId => if deposited into address(this).
    mapping(address => mapping(uint256 => bool)) tokenDeposited;


    // ~ Constructor ~

    /**
     * @notice Initializes Baskets contract.
     */
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    
    // ~ External Functions ~

    /**
     * @notice This method allows a user to deposit their TNFT in exchange for Basket tokens.
     */
    function depositNft(address _tangibleNFT, uint256 _tokenId) external {
        require(!tokenDeposited[_tangibleNFT][_tokenId], "Token already deposited");
    }

    /**
     * @notice This method allows a user to redeem a TNFT in exchange for their Basket tokens.
     */
    function redeemNft(address _tangibleNFT, uint256 _tokenId) external {}

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }


    // ~ Internal Functions ~

    /**
     * @notice This method fetches the USD value of the TNFT being deposited.
     */
    function _getUsdValueOfNft(address _tangibleNFT, uint256 _tokenId) internal {}

    /**
     * @notice This method fetches the USD value of the Basket tokens.
     */
    function _getUsdValueOfBasketTokens() internal {}
}
