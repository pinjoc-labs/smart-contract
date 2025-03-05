// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Mock Oracle Interface
/// @notice Interface for a simple mock price oracle implementation
/// @dev Used for testing purposes to simulate price feeds
interface IMockOracle {
    /// @notice Error thrown when an invalid price is provided
    /// @dev Thrown when attempting to set a price that doesn't meet requirements
    error InvalidPrice();
    
    /// @notice Get the current price from the oracle
    /// @dev Returns the most recently set price
    /// @return The current price value
    function price() external view returns (uint256);

    /// @notice Set a new price in the oracle
    /// @dev Can only be called by the contract owner
    /// @param _price The new price value to set
    /// @custom:throws InvalidPrice if the price is invalid
    function setPrice(uint256 _price) external;
}