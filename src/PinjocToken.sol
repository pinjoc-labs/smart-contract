// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/// @title PinjocToken
/// @notice A specialized ERC20 token representing lending positions in the Pinjoc protocol
/// @dev Implements position tracking with dynamic naming based on debt/collateral pair
/// @custom:security-contact security@pinjoc.com
contract PinjocToken is Ownable, ERC20 {
    using Strings for uint256;

    /// @notice Error thrown when invalid token information is provided
    /// @dev Thrown when any required field in PinjocTokenInfo is zero or empty
    /// @custom:error Thrown when:
    /// @custom:error - debtToken is zero address
    /// @custom:error - collateralToken is zero address
    /// @custom:error - rate is zero
    /// @custom:error - maturity is in the past
    /// @custom:error - maturityMonth is empty string
    /// @custom:error - maturityYear is zero
    error InvalidPinjocTokenInfo();

    /// @notice Structure containing all relevant information for a Pinjoc token
    /// @dev Used to store and manage token-specific parameters
    /// @param debtToken Address of the token being borrowed
    /// @param collateralToken Address of the token used as collateral
    /// @param rate Interest rate for the lending position (in basis points)
    /// @param maturity Timestamp when the lending position matures
    /// @param maturityMonth String representation of maturity month (e.g., "JAN")
    /// @param maturityYear Year of maturity
    struct PinjocTokenInfo {
        address debtToken;
        address collateralToken;
        uint256 rate;
        uint256 maturity;
        string maturityMonth;
        uint256 maturityYear;
    }

    /// @notice Information about the current Pinjoc token instance
    /// @dev Stores all relevant parameters for this specific token
    PinjocTokenInfo public info;

    /// @notice Creates a new Pinjoc token instance
    /// @dev Initializes the token with a dynamic name and symbol based on the provided parameters
    /// @param lendingPool_ Address of the lending pool that will own this token
    /// @param info_ Struct containing all token parameters
    constructor(
        address lendingPool_,
        PinjocTokenInfo memory info_
    ) 
        Ownable(lendingPool_)
        ERC20(
            string(
                abi.encodePacked(
                    "POC ",
                    IERC20Metadata(info_.debtToken).symbol(), "/", IERC20Metadata(info_.collateralToken).symbol(),
                    " ",
                    (info_.rate / 1e14).toString(), "RATE",
                    " ",
                    info_.maturityMonth, "-", info_.maturityYear.toString()
                )
            ),
            string(
                abi.encodePacked(
                    "poc",
                    IERC20Metadata(info_.debtToken).symbol(), IERC20Metadata(info_.collateralToken).symbol(),
                    (info_.rate / 1e14).toString(), "R",
                    info_.maturityMonth, info_.maturityYear.toString()
                )
            )
        ) 
    {
        if (
            info_.debtToken == address(0) || 
            info_.collateralToken == address(0) ||
            info_.rate == 0 ||
            info_.maturity <= block.timestamp ||
            bytes(info_.maturityMonth).length == 0 ||
            info_.maturityYear == 0
        ) {
            revert InvalidPinjocTokenInfo();
        }
        info = info_;
    }
    
    /// @notice Returns the number of decimals used for token amounts
    /// @dev Fixed at 18 decimals for consistency with most ERC20 tokens
    /// @return The number of decimals (18)
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    /// @notice Creates new tokens and assigns them to a specified account
    /// @dev Only the lending pool (owner) can mint tokens
    /// @param to_ The address that will receive the minted tokens
    /// @param amount_ The amount of tokens to mint
    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    /// @notice Destroys tokens from a specified account
    /// @dev Only the lending pool (owner) can burn tokens
    /// @param from_ The address to burn tokens from
    /// @param amount_ The amount of tokens to burn
    function burn(address from_, uint256 amount_) external onlyOwner {
        _burn(from_, amount_);
    }
}