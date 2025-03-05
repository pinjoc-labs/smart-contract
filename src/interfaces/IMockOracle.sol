// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMockOracle {
    error InvalidPrice();
    
    function price() external view returns (uint256);
    function setPrice(uint256 _price) external;
}