// SPDX-License-Identifier: ALEX

/*
 * Copyright (c) Capital Market and Technology Association, 2018-2019
 * https://cmta.ch
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

pragma solidity ^0.8.0;

import "C:/Users/Alex Nikolic/Desktop/CFCoding/UseCases/shares/contracts/ERC20shortened..sol";
import "./ArraysUpgradeable.sol";

abstract contract SnapShotModule is ERC20shortened {
    using ArraysUpgradeable for uint256[];

    event SnapshotSchedule(uint256 indexed oldTime, uint256 indexed newTime);
    event SnapshotUnschedule(uint256 indexed time);

    struct Snapshots {
        uint256[] ids;
        uint256[] values;
    }

    bytes32 public constant SNAPSHOOTER_ROLE = keccak256("SNAPSHOOTER_ROLE");
    mapping(address => Snapshots) internal _accountBalanceSnapshots;
    Snapshots private _totalSupplySnapshots;

    uint256 private _currentSnapshot = 0;

    uint256[] private _scheduledSnapshots;
    uint256[] private _pastScheduledSnapshots;

    function _scheduleSnapshot(uint256 time) internal returns (uint256) {
        require(block.timestamp < time, "Snapshot scheduled in the past");
        (bool found, ) = _findScheduledSnapshotIndex(time);
        require(!found, "Snapshot already scheduled for this time");
        _scheduledSnapshots.push(time);
        emit SnapshotSchedule(0, time);
        return time;
    }

    function _rescheduleSnapshot(uint256 oldTime, uint256 newTime)
        internal
        returns (uint256)
    {
        require(block.timestamp < oldTime, "Snapshot already done");
        require(block.timestamp < newTime, "Snapshot scheduled in the past");

        (bool foundNew, ) = _findScheduledSnapshotIndex(newTime);
        require(!foundNew, "Snapshot already scheduled for this time");

        (bool foundOld, uint256 index) = _findScheduledSnapshotIndex(oldTime);
        require(foundOld, "Snapshot not found");

        _scheduledSnapshots[index] = newTime;

        emit SnapshotSchedule(oldTime, newTime);
        return newTime;
    }

    function _unscheduleSnapshot(uint256 time) internal returns (uint256) {
        require(block.timestamp < time, "Snapshot already done");
        (bool found, uint256 index) = _findScheduledSnapshotIndex(time);
        require(found, "Snapshot not found");

        _removeScheduledItem(index);

        emit SnapshotUnschedule(time);

        return time;
    }

    function getNextSnapshots() public view returns (uint256[] memory) {
        return _scheduledSnapshots;
    }

    function snapshotBalanceOf(uint256 time, address owner)
        public
        view
        returns (uint256)
    {
        (bool snapshotted, uint256 value) = _valueAt(
            time,
            _accountBalanceSnapshots[owner]
        );

        return snapshotted ? value : balanceOf(owner);
    }

    function snapshotTotalSupply(uint256 time) public view returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(
            time,
            _totalSupplySnapshots
        );

        return snapshotted ? value : totalSupply();
    }

    // Update balance and/or total supply snapshots before the values are modified. This is implemented
    // in the _beforeTokenTransfer hook, which is executed for _mint, _burn, and _transfer operations.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        _setCurrentSnapshot();
        if (from != address(0)) {
            // for both burn and transfer
            _updateAccountSnapshot(from);
            if (to != address(0)) {
                // transfer
                _updateAccountSnapshot(to);
            } else {
                // burn
                _updateTotalSupplySnapshot();
            }
        } else {
            // mint
            _updateAccountSnapshot(to);
            _updateTotalSupplySnapshot();
        }
    }

    // Binary Search
    function _valueAt(uint256 time, Snapshots storage snapshots)
        private
        view
        returns (bool, uint256)
    {
        // When a valid snapshot is queried, there are three possibilities:
        //  a) The queried value was not modified after the snapshot was taken. Therefore, a snapshot entry was never
        //  created for this id, and all stored snapshot ids are smaller than the requested one. The value that corresponds
        //  to this id is the current one.
        //  b) The queried value was modified after the snapshot was taken. Therefore, there will be an entry with the
        //  requested id, and its value is the one to return.
        //  c) More snapshots were created after the requested one, and the queried value was later modified. There will be
        //  no entry for the requested id: the value that corresponds to it is that of the smallest snapshot id that is
        //  larger than the requested one.
        //
        // In summary, we need to find an element in an array, returning the index of the smallest value that is larger if
        // it is not found, unless said value doesn't exist (e.g. when all values are smaller). Arrays.findUpperBound does
        // exactly this.

        uint256 index = snapshots.ids.findUpperBound(time);

        if (index == snapshots.ids.length) {
            return (false, 0);
        } else {
            return (true, snapshots.values[index]);
        }
    }

    function _updateAccountSnapshot(address account) private {
        _updateSnapshot(_accountBalanceSnapshots[account], balanceOf(account));
    }

    function _updateTotalSupplySnapshot() private {
        _updateSnapshot(_totalSupplySnapshots, totalSupply());
    }

    function _updateSnapshot(Snapshots storage snapshots, uint256 currentValue)
        private
    {
        uint256 current = _getCurrentSnapshot();
        if (_lastSnapshot(snapshots.ids) < current) {
            snapshots.ids.push(current);
            snapshots.values.push(currentValue);
        }
    }

    function _setCurrentSnapshot() internal {
        uint256 time = _findScheduledMostRecentPastSnapshot();
        if (time > 0) {
            _currentSnapshot = time;
            _clearPastScheduled();
        }
    }

    function _getCurrentSnapshot() internal view virtual returns (uint256) {
        return _currentSnapshot;
    }

    function _lastSnapshot(uint256[] storage ids)
        private
        view
        returns (uint256)
    {
        if (ids.length == 0) {
            return 0;
        } else {
            return ids[ids.length - 1];
        }
    }

    function _findScheduledSnapshotIndex(uint256 time)
        private
        view
        returns (bool, uint256)
    {
        for (uint256 i = 0; i < _scheduledSnapshots.length; i++) {
            if (_scheduledSnapshots[i] == time) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function _findScheduledMostRecentPastSnapshot()
        private
        view
        returns (uint256)
    {
        if (_scheduledSnapshots.length == 0) return 0;
        uint256 mostRecent = 0;
        for (uint256 i = 0; i < _scheduledSnapshots.length; i++) {
            if (
                _scheduledSnapshots[i] <= block.timestamp &&
                _scheduledSnapshots[i] > mostRecent
            ) {
                mostRecent = _scheduledSnapshots[i];
            }
        }
        return mostRecent;
    }

    function _clearPastScheduled() private {
        uint256 i = 0;
        while (i < _scheduledSnapshots.length) {
            if (_scheduledSnapshots[i] <= block.timestamp) {
                _removeScheduledItem(i);
            } else {
                i += 1;
            }
        }
    }

    function _removeScheduledItem(uint256 index) private {
        _scheduledSnapshots[index] = _scheduledSnapshots[
            _scheduledSnapshots.length - 1
        ];
        _pastScheduledSnapshots[
            _pastScheduledSnapshots.length
        ] = _scheduledSnapshots[_scheduledSnapshots.length - 1];
        _scheduledSnapshots.pop();
    }

    function showPastScheduledSnapshots()
        public
        view
        returns (uint256[] memory)
    {
        return _pastScheduledSnapshots;
    }

    uint256[50] private __gap;

    /**************************************************************ERC20 TRANSFER FUNCTIONS TO APPLY BEFORETOKEN HOOK***************************************************************
    @dev NECESSARY BECAUSE OF LINEARIZATION OF INHERITANCE, THE ERC20 DOESNT KNOW ABOUT THE BEFORETOKEN FUNCTION DEFINED IN THIS CONTRACT */
    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "0x54");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }
    }
}
