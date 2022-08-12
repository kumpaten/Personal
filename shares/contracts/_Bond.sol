// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "modules/openzeppelin-contracts@4.7.0/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "modules/openzeppelin-contracts@4.7.0/contracts/access/Ownable.sol";

contract LeBond is ERC20Pausable, Ownable {
    error NotOCFcalling();
    error alreadyListed();
    error notInList();
    error onlyTRapproved();
    error LifeCycleOver();

    event ReceivedOCF(address from, uint256 amount);
    event BondDeployed(
        uint256 faceValue,
        uint256 couponRate_per_annum,
        string name,
        string symbol
    );
    event InvestorAdded(uint256 numOfInvestors);

    /* previous whitelist deleted due to unnecessity, because whitelist is already
     * maintained in OCF contract. */
    address[] private _investors;
    mapping(address => bool) private whitelist;

    /* Bond Specifications
    all Rates as BasisPoints, 1% = 100 */
    address private _OCF; // address of OCF contract
    address private _TR; // same TR as in OCF but can be any issuer that is also registered in OCF
    address private _pauser; // roles can be split

    struct Specifications {
        uint256 faceValue;
        uint256 purchaseRate;
        uint256 returnRate;
        uint256 couponRate_per_annum; // INFO: Coupon assumed to be larger than interval for division (coupon/interval) to not result in 0. Coupon can also be calculated wth 18 decimals but i chose basisPoints demonstration
        uint8 coupon_interval; //as information for customer
        uint256 emissionDate;
        uint256 returnDate;
    }

    Specifications public Bond;
    uint256 private immutable _maxAllocation;
    uint256 private _allocationLeft;
    uint8 private immutable _maxStage; //proportional to coupon_intervals

    // _stage = 0 -> issuance
    // _stage = 1 -> pre-lockup
    // _stage = 2 -> pre-coupon
    // _stage = 3 -> pre-expiry
    // _stage = 4 -> over
    uint8 private _stage = 0;

    constructor(
        address OCF,
        address TR,
        address pauser,
        uint256 _faceValue,
        uint256 _purchaseRate,
        uint256 _returnRate,
        uint256 _couponRate_per_annum,
        uint8 _coupon_interval,
        uint256 _emissionDate,
        uint256 _returnDate,
        address[] memory potentialInvestors, // purpose: predetermined investors list for potential OTC clients
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        _OCF = OCF;
        _TR = TR;
        _pauser = pauser;
        Bond.faceValue = _faceValue;
        Bond.purchaseRate = _purchaseRate;
        Bond.returnRate = _returnRate;
        Bond.couponRate_per_annum = _couponRate_per_annum;
        Bond.coupon_interval = _coupon_interval;
        Bond.emissionDate = block.timestamp;
        Bond.returnDate = _returnDate;
        _maxAllocation = ((_faceValue * _purchaseRate) / 10e4); // 4 comes from the basisPoints where 1% (0.1) is 100, and because 100 is still just 1% of 100% which would be 100000 we divide by 100000
        _allocationLeft = _maxAllocation;
        _maxStage = _coupon_interval + 1;

        _investors.push(TR); //include TR as first investor to allow for buybacks
        whitelist[TR] = true;
        for (uint256 i = 0; i < potentialInvestors.length; i++) {
            whitelist[_investors[i]] = true;
        }

        paused();

        emit BondDeployed(_faceValue, _couponRate_per_annum, name_, symbol_);
    }

    /* --------------------------------- FUNCTIONALITY ---------------------------------- */

    /* TRANSFER FUNCTIONS WITH INITIAL TOKEN TRANSFER AS TokenFallback */

    function transfer(address _to, uint256 _value)
        public
        override
        whenNotPaused
        returns (bool success)
    {
        require(whitelisted(_to), "Destination not whitelisted");
        bool res;
        for (uint256 i = 0; i < _investors.length; i++) {
            if (_to == _investors[i]) {
                res = true;
                break;
            }
        }
        if (!res) {
            _investors.push(_to);
            emit InvestorAdded(_investors.length);
        }
        return super.transfer(_to, _value);
    }

    /**
     * @dev Standard ERC223 function that will handle incoming token transfers.
     *
     * @param from  Token sender address.
     * @param value Amount of tokens.
     * @param data  Transaction metadata.
     */
    function tokenFallback(
        address from,
        uint256 value,
        bytes memory data
    ) public {
        if (msg.sender != _OCF) {
            revert NotOCFcalling();
        }
        if (from != _TR) {
            require(_stage == 0, "No buying bonds after initial issuance");
            require(value <= _allocationLeft, "Not enough allocation left");
            // require(whitelisted(from), "Sender not whitelisted"); unsure if necessary, because why would we exclude investors? Only whitelisted OFC holders can invest anyway.
            // TODO: require (data empty);

            _allocationLeft = _allocationLeft - value;
            _mint(from, value);
            if (!whitelisted(from)) {
                addToWhitelist(from);
            }
            _investors.push(from);

            emit ReceivedOCF(from, value);
            emit InvestorAdded(_investors.length);
        }
    }

    /**
     * @dev whitelist functions to add potential -and remove malicious investors */

    function whitelisted(address ad) internal view returns (bool) {
        return whitelist[ad];
    }

    function addToWhitelist(address ad) public onlyOwner {
        if (whitelisted(ad)) {
            revert alreadyListed();
        }
        whitelist[ad] = true;
    }

    function removeFromWhitelist(address ad) public onlyOwner {
        if (!whitelisted(ad)) {
            revert notInList();
        }
        whitelist[ad] = false;
    }

    /**
     * @dev function to switch between stages of bond lifecycle, number of stages defined in constructor corresponding to coupon interval
     */
    // warp time
    function tick() public {
        if (msg.sender != _TR) {
            revert onlyTRapproved();
        }

        if (_stage > _maxStage + 1) {
            revert LifeCycleOver();
        }

        if (_stage == _maxStage + 1) {
            //revert("Already at end of lifecycle");
            IERC20 OCFErc20 = IERC20(_OCF);
            OCFErc20.transfer(_TR, OCFErc20.balanceOf(address(this)));
        }

        if (_stage == _maxStage) {
            // pay coupon, pay principle, burn all tokens
            IERC20 OCFErc20 = IERC20(_OCF);
            uint256 coupon = ((Bond.faceValue * Bond.couponRate_per_annum) /
                Bond.coupon_interval) / 1e4;
            for (uint256 i = 1; i < _investors.length; i++) {
                // (UPDATE: TR is the first one in list)
                uint256 couponPayment = (coupon * /* calculated to represent the actual share of the coupon measured by the purchaseValue */
                    ((balanceOf(_investors[i]) * 1e4) / _maxAllocation)) / 1e4;
                uint256 principlePayment = (Bond.faceValue *
                    ((balanceOf(_investors[i]) * 1e4) / _maxAllocation)) / 1e4;
                OCFErc20.transfer(
                    _investors[i],
                    (couponPayment + principlePayment)
                );
            }

            // destroy all bond tokens
            for (uint256 i = 0; i < _investors.length; i++) {
                _burn(_investors[i], balanceOf(_investors[i]));
            }

            // return any remaining OCF to TR
            OCFErc20.transfer(_TR, OCFErc20.balanceOf(address(this)));
        }

        if (_stage > 1 && _stage < _maxStage) {
            IERC20 OCFErc20 = IERC20(_OCF);
            uint256 coupon = ((Bond.faceValue * Bond.couponRate_per_annum) /
                Bond.coupon_interval) / 1e4;
            for (uint256 i = 1; i < _investors.length; i++) {
                // (UPDATE: TR is the first one in list)
                uint256 couponPayment = (coupon * /* calculated to represent the actual share of the coupon measured by the purchaseValue */
                    ((balanceOf(_investors[i]) * 1e4) / _maxAllocation)) / 1e4;
                OCFErc20.transfer(_investors[i], couponPayment);
            }
        }

        if (_stage == 1) {
            // allow free movement and OTC trading
        }

        if (_stage == 0) {
            // send remaining allocation to TR for OTC trading in Stage 1
            _mint(_TR, _allocationLeft);
            _allocationLeft = 0;
            // send OCF to TR -> taking paid in money as loan
            IERC20 OCFErc20 = IERC20(_OCF);
            OCFErc20.transfer(_TR, OCFErc20.balanceOf(address(this)));
            _unpause();
        }
        _stage++;
    }
}
