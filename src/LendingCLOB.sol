// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ILendingCLOB} from "./interfaces/ILendingCLOB.sol";

/// @title LendingCLOB - A Central Limit Order Book (CLOB) for P2P lending
/// @notice Manages lending and borrowing orders with rate-time priority matching
/// @dev Implements a two-sided order book where LEND and BORROW
contract LendingCLOB is ILendingCLOB, Ownable {
    /// @notice Token that can be borrowed (e.g., USDC)
    IERC20 public immutable debtToken;

    /// @notice Token used as collateral (e.g., WETH)
    IERC20 public immutable collateralToken;

    /// @notice Maturity month of the CLOB
    string public maturityMonth;

    /// @notice Maturity year of the CLOB
    uint256 public immutable maturityYear;

    /// @notice Counter for generating unique order IDs
    uint256 public orderCount;

    /// @notice Current best (lowest) lending rate available
    uint256 public bestLendRate;

    /// @notice Tracks collateral balances for borrowers
    mapping(address => uint256) public collateralBalances;

    /// @notice Tracks debt token balances for lenders
    mapping(address => uint256) public debtBalances;

    /// @notice Maps traders to their orders
    mapping(address => Order[]) public traderOrders;

    /// @notice Main order book storage: rate => side => orders
    /// @dev Primary structure for order matching and rate discovery
    mapping(uint256 => mapping(Side => Order[])) public orderQueue;

    /// @notice Creates a new lending order book
    /// @param _debtToken Address of the debt token
    /// @param _collateralToken Address of the collateral token
    /// @param _maturityMonth Maturity month of the CLOB
    /// @param _maturityYear Maturity year of the CLOB
    constructor(
        address _router,
        address _debtToken,
        address _collateralToken,
        string memory _maturityMonth,
        uint256 _maturityYear
    ) Ownable(_router) {
        debtToken = IERC20(_debtToken);
        collateralToken = IERC20(_collateralToken);
        maturityMonth = _maturityMonth;
        maturityYear = _maturityYear;
        bestLendRate = 100e16; // 100%
    }

    /// @notice Updates the best lend rate based on the order queue
    /// @dev Scans through lend orders to find the lowest valid rate
    function _updateBestLendRate() internal {
        uint256 lowestRate = type(uint256).max;
        bool foundValidRate = false;

        // Iterate through all orders to find lowest rate with valid orders
        // Since rate is rate, then range will be from 0.5% (5e15) to 99.5% (995e15)
        // We increment by 0.5% (5e15)
        for (uint256 rate = 5e15; rate < 995e15; rate += 5e15) {
            Order[] storage orders = orderQueue[rate][Side.LEND];
            for (uint256 i = 0; i < orders.length; i++) {
                if (orders[i].status == Status.OPEN) {
                    lowestRate = rate;
                    foundValidRate = true;
                    break;
                }
            }
            if (foundValidRate) break;
        }

        // Only update and emit if rate changed
        if (bestLendRate != lowestRate) {
            bestLendRate = lowestRate;
            emit BestRateUpdated(lowestRate, Side.LEND);
        }
    }

    /// @notice Gets the current best (lowest) lending rate available
    /// @return The best lending rate, or max uint256 if no valid lending orders exist
    function getBestLendRate() external view returns (uint256) {
        return (bestLendRate == 100e16) ? 0 : bestLendRate;
    }

    /// @notice Places a new order in the book
    /// @dev Handles both lending and borrowing orders
    /// @param trader Address of the trader placing the order
    /// @param amount Amount of tokens to lend/borrow
    /// @param collateralAmount Amount of collateral (for BORROW orders)
    /// @param rate Interest rate in basis points
    /// @param side LEND or BORROW
    /// @return matchedLendOrders Array of matched lending orders
    /// @return matchedBorrowOrders Array of matched borrowing orders
    function placeOrder(
        address trader,
        uint256 amount,
        uint256 collateralAmount,
        uint256 rate,
        Side side
    )
        external
        onlyOwner
        returns (
            MatchedInfo[] memory matchedLendOrders,
            MatchedInfo[] memory matchedBorrowOrders
        )
    {
        // ---------------------------
        // 1. Transfer tokens to escrow
        // ---------------------------
        // Remember owner is router!
        if (side == Side.LEND) {
            // LEND => deposit debtToken
            debtBalances[trader] += amount;
            debtToken.transferFrom(owner(), address(this), amount);
            emit Deposit(trader, amount, Side.LEND);
        } else {
            // BORROW => deposit collateralToken
            collateralBalances[trader] += collateralAmount;
            collateralToken.transferFrom(
                owner(),
                address(this),
                collateralAmount
            );
            emit Deposit(trader, collateralAmount, Side.BORROW);
        }

        // ---------------------------
        // 2. Build the new order
        // ---------------------------
        uint256 orderId = orderCount;
        orderCount++;

        Order memory newOrder = Order({
            id: orderId,
            trader: trader,
            amount: amount,
            collateralAmount: collateralAmount,
            rate: rate,
            side: side,
            status: Status.OPEN
        });

        emit OrderPlaced(
            orderId,
            trader,
            amount,
            collateralAmount,
            rate,
            side,
            Status.OPEN
        );

        // Arrays to store matched results, 50 is arbitrary max
        MatchedInfo[] memory tempLendMatches = new MatchedInfo[](50);
        MatchedInfo[] memory tempBorrowMatches = new MatchedInfo[](50);
        uint256 lendMatchCount = 0;
        uint256 borrowMatchCount = 0;

        // Opposite side
        Side oppositeSide = (side == Side.LEND) ? Side.BORROW : Side.LEND;
        Order[] storage oppQueue = orderQueue[rate][oppositeSide];

        // Keep track of total matched for the newOrder
        uint256 totalMatchedForNewOrder;
        uint256 originalNewAmount = newOrder.amount;

        // ---------------------------
        // 3. Match loop
        // ---------------------------
        uint256 i = 0;
        while (i < oppQueue.length && newOrder.amount > 0) {
            Order storage matchOrder = oppQueue[i];

            // Skip if FILLED, CANCELLED, or same trader
            if (
                matchOrder.status == Status.FILLED ||
                matchOrder.status == Status.CANCELLED ||
                matchOrder.trader == trader
            ) {
                i++;
                continue;
            }

            uint256 originalMatchAmount = matchOrder.amount;
            uint256 matchedAmount = 0;

            if (matchOrder.amount <= newOrder.amount) {
                // matchOrder fully filled
                matchedAmount = matchOrder.amount;
                newOrder.amount -= matchedAmount;
                matchOrder.amount = 0;
                matchOrder.status = Status.FILLED;

                if (newOrder.amount == 0) {
                    newOrder.status = Status.FILLED;
                } else {
                    newOrder.status = Status.PARTIALLY_FILLED;
                }

                emit OrderMatched(
                    newOrder.id,
                    matchOrder.id,
                    newOrder.status,
                    Status.FILLED
                );

                // Record how many tokens the newOrder matched
                totalMatchedForNewOrder += matchedAmount;

                // store matchOrder details
                _storeMatchInfo(
                    matchOrder,
                    matchedAmount,
                    originalMatchAmount,
                    tempLendMatches,
                    tempBorrowMatches,
                    lendMatchCount,
                    borrowMatchCount
                );
                if (matchOrder.side == Side.LEND) {
                    lendMatchCount++;
                } else {
                    borrowMatchCount++;
                }

                // Remove matchOrder from queue (swap + pop)
                _removeFromQueueByIndex(oppQueue, i, rate, matchOrder.side);
            } else {
                // newOrder is fully filled, matchOrder partial
                matchedAmount = newOrder.amount;
                matchOrder.amount -= matchedAmount;
                matchOrder.status = Status.PARTIALLY_FILLED;
                newOrder.amount = 0;
                newOrder.status = Status.FILLED;

                emit OrderMatched(
                    newOrder.id,
                    matchOrder.id,
                    Status.FILLED,
                    Status.PARTIALLY_FILLED
                );

                totalMatchedForNewOrder += matchedAmount;

                // matchOrder
                _storeMatchInfo(
                    matchOrder,
                    matchedAmount,
                    originalMatchAmount,
                    tempLendMatches,
                    tempBorrowMatches,
                    lendMatchCount,
                    borrowMatchCount
                );
                if (matchOrder.side == Side.LEND) {
                    lendMatchCount++;
                } else {
                    borrowMatchCount++;
                }

                // newOrder is exhausted => break
                i++;
                break;
            }

            i++;
        }

        // ----------------------------------
        // 4. If newOrder is STILL OPEN
        // ----------------------------------
        if (newOrder.status == Status.OPEN) {
            // No fill happened; push entire order
            orderQueue[newOrder.rate][newOrder.side].push(newOrder);
            traderOrders[newOrder.trader].push(newOrder);
        } else {
            // (FILLED or PARTIALLY_FILLED)
            // We record it once in traderOrders
            traderOrders[newOrder.trader].push(newOrder);
        }

        // ----------------------------------
        // 5. *Now* store newOrder's matched info if it partially or fully filled
        //    (Because newOrder is only one, we do this exactly once).
        // ----------------------------------
        if (totalMatchedForNewOrder > 0) {
            // We'll store newOrder's final leftover
            // partial fill leftover = newOrder.amount
            // final status is newOrder.status
            // matched fraction = totalMatchedForNewOrder / originalNewAmount

            // Calculate matched collateral amount proportionally
            uint256 matchedCollateralAmount = 0;
            if (newOrder.side == Side.BORROW) {
                matchedCollateralAmount =
                    (newOrder.collateralAmount * totalMatchedForNewOrder) /
                    originalNewAmount;
            }

            MatchedInfo memory newOrderInfo = MatchedInfo({
                orderId: newOrder.id,
                trader: newOrder.trader,
                matchAmount: totalMatchedForNewOrder,
                matchCollateralAmount: matchedCollateralAmount,
                side: newOrder.side,
                status: newOrder.status
            });

            // If newOrder is LEND, add to lend array; else to borrow array
            if (newOrder.side == Side.LEND) {
                tempLendMatches[lendMatchCount] = newOrderInfo;
                lendMatchCount++;
            } else {
                tempBorrowMatches[borrowMatchCount] = newOrderInfo;
                borrowMatchCount++;
            }
        }

        // ----------------------------------
        // 6. Build final matched arrays
        // ----------------------------------
        matchedLendOrders = new MatchedInfo[](lendMatchCount);
        matchedBorrowOrders = new MatchedInfo[](borrowMatchCount);

        uint256 lendIdx = 0;
        uint256 borrowIdx = 0;

        // copy lend matches
        for (uint256 j = 0; j < 50; j++) {
            MatchedInfo memory infoL = tempLendMatches[j];
            if (infoL.trader != address(0)) {
                matchedLendOrders[lendIdx] = infoL;
                lendIdx++;
                if (lendIdx == lendMatchCount) break;
            }
        }

        // copy borrow matches
        for (uint256 k = 0; k < 50; k++) {
            MatchedInfo memory infoB = tempBorrowMatches[k];
            if (infoB.trader != address(0)) {
                matchedBorrowOrders[borrowIdx] = infoB;
                borrowIdx++;
                if (borrowIdx == borrowMatchCount) break;
            }
        }

        // After matching logic, update best rate if this is a lend order
        if (side == Side.LEND && newOrder.status == Status.OPEN) {
            if (rate < bestLendRate) {
                bestLendRate = rate;
                emit BestRateUpdated(rate, Side.LEND);
            }
        }

        // Return both arrays
        return (matchedLendOrders, matchedBorrowOrders);
    }

    /// @notice Cancels an open order
    /// @dev Refunds escrowed tokens and updates order status
    /// @param trader Address of the trader who placed the order
    /// @param orderId ID of the order to cancel
    function cancelOrder(address trader, uint256 orderId) external onlyOwner {
        Order[] storage orders = traderOrders[trader];
        bool isOrderFound = false;
        for (uint256 i = 0; i < orders.length; i++) {
            if (
                orders[i].id == orderId &&
                (orders[i].status == Status.OPEN ||
                    orders[i].status == Status.PARTIALLY_FILLED)
            ) {
                Order storage orderFound = orders[i];
                orderFound.status = Status.CANCELLED;
                emit LimitOrderCancelled(orderId, Status.CANCELLED);

                // Remove from queue if present
                uint256 idx = _findOrderIndex(
                    orderQueue[orderFound.rate][orderFound.side],
                    orderId
                );
                if (idx < orderQueue[orderFound.rate][orderFound.side].length) {
                    _removeFromQueueByIndex(
                        orderQueue[orderFound.rate][orderFound.side],
                        idx,
                        orderFound.rate,
                        orderFound.side
                    );

                    // If this was a lend order and potentially the best rate, update best rate
                    if (
                        orderFound.side == Side.LEND &&
                        orderFound.rate == bestLendRate
                    ) {
                        _updateBestLendRate();
                    }
                }

                // Refund escrow
                if (orderFound.side == Side.LEND) {
                    uint256 refundAmount = orderFound.amount;
                    if (debtBalances[trader] >= refundAmount) {
                        debtBalances[trader] -= refundAmount;
                        debtToken.transfer(trader, refundAmount);
                    } else {
                        revert InsufficientBalance(
                            trader,
                            address(debtToken),
                            debtBalances[trader],
                            refundAmount
                        );
                    }
                } else {
                    uint256 refundCollat = orderFound.collateralAmount;
                    if (collateralBalances[trader] >= refundCollat) {
                        collateralBalances[trader] -= refundCollat;
                        collateralToken.transfer(trader, refundCollat);
                    } else {
                        revert InsufficientBalance(
                            trader,
                            address(collateralToken),
                            collateralBalances[trader],
                            refundCollat
                        );
                    }
                }
                isOrderFound = true;
                break;
            }
        }
        if (!isOrderFound) revert OrderNotFound();
    }

    /// @notice Transfers tokens between parties
    /// @dev Only callable by owner (e.g., router contract)
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param amount Amount of tokens to transfer
    /// @param side Determines which token to transfer (LEND=debt, BORROW=collateral)
    function transferFrom(
        address from,
        address to,
        uint256 amount,
        Side side
    ) external onlyOwner {
        if (side == Side.LEND) {
            if (debtBalances[from] >= amount) {
                debtBalances[from] -= amount;
                debtToken.transfer(to, amount);
            } else {
                revert InsufficientBalance(
                    from,
                    address(debtToken),
                    debtBalances[from],
                    amount
                );
            }
        } else {
            if (collateralBalances[from] >= amount) {
                collateralBalances[from] -= amount;
                collateralToken.transfer(to, amount);
            } else {
                revert InsufficientBalance(
                    from,
                    address(collateralToken),
                    collateralBalances[from],
                    amount
                );
            }
        }
        emit Transfer(from, to, amount, side);
    }

    /// @notice Gets all orders placed by a trader
    /// @param trader Address of the trader
    /// @return Array of orders placed by the trader
    function getUserOrders(
        address trader
    ) external view returns (Order[] memory) {
        return traderOrders[trader];
    }

    /// @notice Stores match information for an order
    /// @dev Helper function for tracking matched orders
    /// @param matchOrder The order that was matched
    /// @param matchedAmount Amount that was matched
    /// @param originalMatchAmount Original order amount
    /// @param lendArr Array to store LEND matches
    /// @param borrowArr Array to store BORROW matches
    /// @param lendCount Current count of LEND matches
    /// @param borrowCount Current count of BORROW matches
    function _storeMatchInfo(
        Order storage matchOrder,
        uint256 matchedAmount,
        uint256 originalMatchAmount,
        MatchedInfo[] memory lendArr,
        MatchedInfo[] memory borrowArr,
        uint256 lendCount,
        uint256 borrowCount
    ) internal {
        // Calculate matched collateral amount proportionally
        uint256 matchedCollateralAmount = 0;
        if (matchOrder.side == Side.BORROW) {
            // For borrow orders, calculate collateral proportionally
            matchedCollateralAmount =
                (matchOrder.collateralAmount * matchedAmount) /
                originalMatchAmount;
        }

        MatchedInfo memory info = MatchedInfo({
            orderId: matchOrder.id,
            trader: matchOrder.trader,
            matchAmount: matchedAmount,
            matchCollateralAmount: matchedCollateralAmount,
            side: matchOrder.side,
            status: matchOrder.status
        });

        _updateTraderOrderStatus(
            matchOrder.id,
            matchOrder.trader,
            originalMatchAmount - matchedAmount,
            matchOrder.collateralAmount - matchedCollateralAmount,
            matchOrder.status
        );

        if (matchOrder.side == Side.LEND) {
            lendArr[lendCount] = info;
        } else {
            borrowArr[borrowCount] = info;
        }
    }

    /// @notice Removes an order from the queue
    /// @dev Helper function for order cancellation and matching
    /// @param queue The order queue to remove from
    /// @param index Index of the order to remove
    /// @param rate Rate level of the order
    /// @param side Side of the order book
    function _removeFromQueueByIndex(
        Order[] storage queue,
        uint256 index,
        uint256 rate,
        Side side
    ) internal {
        uint256 length = queue.length;
        if (length > 0 && index < length) {
            uint256 rmOrderId = queue[index].id;
            queue[index] = queue[length - 1];
            queue.pop();

            emit OrderRemovedFromQueue(rmOrderId, rate, side);
        }
    }

    /// @notice Finds the index of an order in the queue
    /// @dev Helper function for order cancellation
    /// @param orders Array of orders to search
    /// @param orderId ID of the order to find
    /// @return Index of the order, or max uint256 if not found
    function _findOrderIndex(
        Order[] storage orders,
        uint256 orderId
    ) internal view returns (uint256) {
        for (uint256 i = 0; i < orders.length; i++) {
            // Only remove if status == OPEN
            if (orders[i].id == orderId && orders[i].status == Status.OPEN) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function _updateTraderOrderStatus(
        uint256 orderId,
        address trader,
        uint256 amount,
        uint256 collateralAmount,
        Status status
    ) internal {
        Order[] storage orders = traderOrders[trader];
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].id == orderId) {
                orders[i].amount = amount;
                orders[i].collateralAmount = collateralAmount;
                orders[i].status = status;
                break;
            }
        }
    }
}
