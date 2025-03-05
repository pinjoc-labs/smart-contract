// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IMockOracle} from "../interfaces/IMockOracle.sol";

/// @title MockOracle
/// @notice A mock price oracle contract for testing purposes
/// @dev Simulates a price feed oracle with manual price setting capability
contract MockOracle is Ownable, IMockOracle {
    /// @notice Address of the base token price feed
    address public baseFeed;
    /// @notice Address of the quote token price feed
    address public quoteFeed;
    /// @notice Current price with 18 decimals precision
    uint256 public price;

    /// @notice Initializes the mock oracle with base and quote feed addresses
    /// @param baseFeed_ Address of the base token price feed
    /// @param quoteFeed_ Address of the quote token price feed
    constructor(address baseFeed_, address quoteFeed_) Ownable(msg.sender) {
        baseFeed = baseFeed_;
        quoteFeed = quoteFeed_;
    }

    /// @notice Sets a new price in the oracle
    /// @dev Only callable by the contract owner
    /// @param price_ New price value with 18 decimals precision
    /// @custom:throws InvalidPrice if price is zero
    function setPrice(uint256 price_) external onlyOwner {
        if (price_ == 0) revert InvalidPrice();
        price = price_;
    }
}