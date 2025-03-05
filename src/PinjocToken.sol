// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/// @title PinjocToken
/// @notice ERC20 token representing a position in Pinjoc lending protocol
/// @dev Token name format: "POC DEBT/COLLATERAL RATE-XXXX MMM-YYYY"
/// @dev Token symbol format: "pocDEBTCOLLATERALXXXXRMMMYYYY"
contract PinjocToken is Ownable, ERC20 {
    using Strings for uint256;

    /// @notice The debt token address (e.g., USDC)
    address public immutable debtToken;
    /// @notice The collateral token address (e.g., ETH)
    address public immutable collateralToken;
    /// @notice The borrow rate with 18 decimals (1e18 = 100%)
    uint256 public immutable rate;
    /// @notice The maturity timestamp
    uint256 public immutable maturity;
    /// @notice The maturity month in string format (e.g., "MAR")
    string public maturityMonth;
    /// @notice The maturity year
    uint256 public immutable maturityYear;

    /// @notice Creates a new Pinjoc token
    /// @param lendingPool_ The address of the lending pool contract
    /// @param debtToken_ The address of the debt token
    /// @param collateralToken_ The address of the collateral token
    /// @param rate_ The borrow rate with 18 decimals (45e16 = 45%, 455e15 = 45.5%)
    /// @param maturity_ The maturity timestamp
    /// @param maturityMonth_ The maturity month in string format (e.g., "MAR")
    /// @param maturityYear_ The maturity year
    constructor(
        address lendingPool_,
        address debtToken_,
        address collateralToken_,
        uint256 rate_,
        uint256 maturity_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) 
        Ownable(lendingPool_)
        ERC20(
            string(
                abi.encodePacked(
                    "POC ",
                    IERC20Metadata(debtToken_).symbol(), "/", IERC20Metadata(collateralToken_).symbol(),
                    " ",
                    (rate_ / 1e14).toString(), "RATE",
                    " ",
                    maturityMonth_, "-", maturityYear_.toString()
                )
            ),
            string(
                abi.encodePacked(
                    "poc",
                    IERC20Metadata(debtToken_).symbol(), IERC20Metadata(collateralToken_).symbol(),
                    (rate_ / 1e14).toString(), "R",
                    maturityMonth_, maturityYear_.toString()
                )
            )
        ) 
    {
        debtToken = debtToken_;
        collateralToken = collateralToken_;
        rate = rate_;
        maturity = maturity_;
        maturityMonth = maturityMonth_;
        maturityYear = maturityYear_;
    }
    
    /// @notice Returns the number of decimals used for token amounts
    /// @return The number of decimals (18)
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    /// @notice Mints new tokens to a specified account
    /// @dev Only callable by the lending pool (owner)
    /// @param to_ The address that will receive the minted tokens
    /// @param amount_ The amount of tokens to mint
    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    /// @notice Burns tokens from a specified account
    /// @dev Only callable by the lending pool (owner)
    /// @param from_ The address to burn tokens from
    /// @param amount_ The amount of tokens to burn
    function burn(address from_, uint256 amount_) external onlyOwner {
        _burn(from_, amount_);
    }
}