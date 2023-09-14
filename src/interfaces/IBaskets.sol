// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IBasket is IERC20, IERC20Metadata {

    struct TokenData {
        address tnft;
        uint256 tokenId;
        uint256 fingerprint;
    }
    
    function getDepositedTnfts() external view returns (TokenData[] memory);

    function getSupportedRentTokens() external view returns (address[] memory);

    function getSupportedFeatures() external view returns (uint256[] memory);

    function tokenDeposited(address, uint256) external returns (bool);

    function featureSupported(uint256) external returns (bool);

    function currencySupported(string memory) external returns (bool);

    function currencyBalance(string memory) external returns (uint256);

    function tnftType() external returns (uint256);

    function batchDepositTNFT(
        address[] memory _tangibleNFTs,
        uint256[] memory _tokenIds
    ) external returns (uint256[] memory basketShares);

    function depositTNFT(
        address _tangibleNFT,
        uint256 _tokenId
    ) external returns (uint256 basketShare);

    function modifyRentTokenSupport(address _token, bool _support) external;

    function getSharePrice() external view returns (uint256 sharePrice);

    function getTotalValueOfBasket() external view returns (uint256 totalValue);
}