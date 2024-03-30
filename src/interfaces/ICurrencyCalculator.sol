// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

/// @title ICurrencyCalculator interface defines the interface of the CurrencyCalculator contract.
interface ICurrencyCalculator {

    function getUSDValue(address _tangibleNFT, uint256 _tokenId) external view returns (uint256);

    function getTnftNativeValue(address _tangibleNFT, uint256 _fingerprint) external view returns (string memory currency, uint256 value, uint8 decimals);

    function getUsdExchangeRate(string memory _currency) external view returns (uint256 exchangeRate, uint256 decimals);
}