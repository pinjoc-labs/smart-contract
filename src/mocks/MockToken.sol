// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MockToken
/// @notice A mock ERC20 token implementation for testing purposes
/// @dev Extends OpenZeppelin's ERC20 and Ownable contracts
contract MockToken is Ownable, ERC20 {
    /// @notice Token decimals storage
    uint8 private _decimals;

    /// @notice Constructs a new MockToken instance
    /// @dev Sets up the token with a name, symbol, and decimal places
    /// @param name_ The name of the token
    /// @param symbol_ The symbol of the token
    /// @param decimals_ The number of decimal places for token amounts
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) Ownable(msg.sender) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /// @notice Mints new tokens to a specified account
    /// @dev Only callable by the contract owner
    /// @param account_ The address to receive the minted tokens
    /// @param amount_ The amount of tokens to mint
    function mint(address account_, uint256 amount_) external onlyOwner {
        _mint(account_, amount_);
    }

    /// @notice Burns tokens from the owner's account
    /// @dev Only callable by the contract owner
    /// @param amount_ The amount of tokens to burn
    function burn(uint256 amount_) external onlyOwner {
        _burn(msg.sender, amount_);
    }

    /// @notice Returns the number of decimals used for token amounts
    /// @dev Overrides the ERC20 decimals() function
    /// @return The number of decimals places for token amounts
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}