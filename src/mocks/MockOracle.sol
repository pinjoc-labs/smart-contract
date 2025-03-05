// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockOracle is Ownable {
    // error
    error InvalidPrice();

    address public baseFeed;
    address public quoteFeed;
    uint256 public price;

    constructor(address _baseFeed, address _quoteFeed) Ownable(msg.sender) {
        baseFeed = _baseFeed;
        quoteFeed = _quoteFeed;
    }

    function setPrice(uint256 _price) external onlyOwner {
        if (_price == 0) revert InvalidPrice();
        price = _price;
    }

    // only for checking deploy script
    function getPrice() external view returns (uint256) {
        return price;
    }
}