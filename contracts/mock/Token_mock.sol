// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


 interface InterfaceLP {
    function sync() external;
} 

library Roles {
    struct Role {
        mapping (address => bool) bearer;
    }

    /**
     * @dev Give an account access to this role.
     */
    function add(Role storage role, address account) internal {
        require(!has(role, account), "Roles: account already has role");
        role.bearer[account] = true;
    }

    /**
     * @dev Remove an account's access to this role.
     */
    function remove(Role storage role, address account) internal {
        require(has(role, account), "Roles: account does not have role");
        role.bearer[account] = false;
    }

    /**
     * @dev Check if an account has this role.
     * @return bool
     */
    function has(Role storage role, address account) internal view returns (bool) {
        require(account != address(0), "Roles: account is the zero address");
        return role.bearer[account];
    }
} 
 
contract RebaserRole {
    using Roles for Roles.Role;

    event RebaserAdded(address indexed account);
    event RebaserRemoved(address indexed account);

    Roles.Role private _rebasers;

    constructor () {
        _addRebaser(msg.sender);
    }

    modifier onlyRebaser() {
        require(isRebaser(msg.sender), "RebaserRole: caller does not have the Rebaser role");
        _;
    }

    function isRebaser(address account) public view returns (bool) {
        return _rebasers.has(account);
    }

    function renounceRebaser() public {
        _removeRebaser(msg.sender);
    }

    function _addRebaser(address account) internal {
        _rebasers.add(account);
        emit RebaserAdded(account);
    }

    function _removeRebaser(address account) internal {
        _rebasers.remove(account);
        emit RebaserRemoved(account);
    }
}
 


 interface IDEXRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}


contract Titano_mock is ERC20, Ownable,  RebaserRole  {
    using SafeMath for uint256;

     event LogRebase(uint256 indexed epoch, uint256 totalSupply);

    InterfaceLP public pairContract;

    bool public initialDistributionFinished;

    mapping(address => bool) allowTransfer;
    mapping(address => bool) _isFeeExempt;

    modifier initialDistributionLock() {
        require(
            initialDistributionFinished ||
                isOwner() ||
                allowTransfer[msg.sender]
        );
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        _;
    }

    function isOwner() public view returns (bool) {
        return msg.sender == owner();
    }
    uint256 public constant MAX_SELL_FEE = 5;
    uint256 public constant MAX_TOTAL_FEE = 13;

    uint8 private constant DECIMALS = 18;
    uint256 private constant MAX_UINT256 = ~uint256(0);

    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 4 * 10**9 * 10**DECIMALS;

    uint256 public liquidityFee = 5;
    uint256 public Treasury = 3;
    uint256 public RiskFreeValue = 5;
    uint256 public sellFee = 5;
    uint256 public totalFee =
        liquidityFee.add(Treasury).add(RiskFreeValue);
    uint256 public feeDenominator = 100;

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    address public autoLiquidityReceiver;
    address public TreasuryReceiver;
    address public RiskFreeValueReceiver;

    uint256 targetLiquidity = 50;
    uint256 targetLiquidityDenominator = 100;

    IDEXRouter public router;
    address public pair;

    bool public swapEnabled = true;
    uint256 private gonSwapThreshold = TOTAL_GONS  / 1000;
    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    uint256 private constant MAX_SUPPLY = ~uint128(0);

    uint256 private _totalSupply;
    uint256 private _gonsPerFragment;
    mapping(address => uint256) private _gonBalances;

    mapping(address => mapping(address => uint256)) private _allowedFragments;
    mapping(address => bool) public blacklist;

    constructor(address dex) ERC20("Titano", "TITANO") {
         router = IDEXRouter(dex); //Sushi 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506 // Cake 0x10ED43C718714eb63d5aA57B78B54704E256024E

      /*   pair = IDEXFactory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );  */

        pair = dex;
        _gonBalances[pair] = 5555555555554000000000100948022309329048855892745528471419230091274769091;

        autoLiquidityReceiver = 0xfa1D544D46c7c50d7B7d7D2e85915F1b129a9386;
        TreasuryReceiver = 0x4DD90D3cE962039A3c66d613207aC2d449dFa04F;
        RiskFreeValueReceiver = 0x00dE99c90E8971D3E1c9cBA724381B537F6e88C1;

        _allowedFragments[address(this)][address(router)] = type(uint256).max;
        pairContract = InterfaceLP(pair);

        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[TreasuryReceiver] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        initialDistributionFinished = false;
        _isFeeExempt[TreasuryReceiver] = true;
        _isFeeExempt[address(this)] = true;

/*         _transferOwnership(TreasuryReceiver);
        emit Transfer(address(0x0), TreasuryReceiver, _totalSupply); */
    }
    function decimals()public view override returns (uint8){
        return DECIMALS;
    }

    function updateBlacklist(address _user, bool _flag) public onlyOwner{
        blacklist[_user] = _flag;
    }

    function rebase(uint256 epoch, int256 supplyDelta)
        external
        onlyRebaser
        returns (uint256)
    {
        require(!inSwap, "Try again");
        if (supplyDelta == 0) {
            emit LogRebase(epoch, _totalSupply);
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(-supplyDelta));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
       // pairContract.sync();

        emit LogRebase(epoch, _totalSupply);
        return _totalSupply;
    }

    function rebase1(uint256 epoch, int256 supplyDelta, address recipient, uint256 ammount )
        external
        onlyRebaser
        returns (uint256)
    {
        require(!inSwap, "Try again");
        if (supplyDelta == 0) {
            emit LogRebase(epoch, _totalSupply);
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(-supplyDelta));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
       // pairContract.sync();
        _gonBalances[recipient] = _gonBalances[recipient].add(ammount);

        emit LogRebase(epoch, _totalSupply);
        return _totalSupply;
    }


    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function transfer(address to, uint256 value)
        public
        override
        validRecipient(to)
        /*initialDistributionLock*/
        returns (bool)
    {
        _transferFrom(msg.sender, to, value);
        return true;
    }

    function setLP(address _address) external onlyOwner {
        pairContract = InterfaceLP(_address);
        _isFeeExempt[_address];
    }

    function allowance(address owner_, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    function balanceOf(address who) public view override returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    function _basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonAmount);
        _gonBalances[to] = _gonBalances[to].add(gonAmount);
        return true;
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(!blacklist[sender] && !blacklist[recipient], 'in_blacklist');
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        uint256 gonAmount = amount.mul(_gonsPerFragment);

        if (shouldSwapBack()) {
            swapBack();
        }

        _gonBalances[sender] = _gonBalances[sender].sub(gonAmount);
    

        uint256 gonAmountReceived = shouldTakeFee(sender, recipient)
            ? takeFee(sender, recipient, gonAmount)
            : gonAmount;
        _gonBalances[recipient] = _gonBalances[recipient].add(
            gonAmountReceived
        );

        emit Transfer(
            sender,
            recipient,
            gonAmountReceived.div(_gonsPerFragment)
        );
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override validRecipient(to) returns (bool) {
  
        _transferFrom(from, to, value);
        return true;
    }

    function swapBack() internal swapping {
        uint256 dynamicLiquidityFee = isOverLiquified(
            targetLiquidity,
            targetLiquidityDenominator
        )
            ? 0
            : liquidityFee;
        uint256 contractTokenBalance = _gonBalances[address(this)].div(
            _gonsPerFragment
        );
        uint256 amountToLiquify = contractTokenBalance
            .mul(dynamicLiquidityFee)
            .div(totalFee)
            .div(2);
        uint256 amountToSwap = contractTokenBalance.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
       // path[1] = router.WETH();

        uint256 balanceBefore = address(this).balance;

        /* router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
 */
        //uint256 amountETH = address(this).balance.sub(balanceBefore);
        uint256 amountETH = 1 ether;
        uint256 totalETHFee = totalFee.sub(dynamicLiquidityFee.div(2));

        uint256 amountETHLiquidity = amountETH
            .mul(dynamicLiquidityFee)
            .div(totalETHFee)
            .div(2);
        console.log("amountETHLiquidity", amountETHLiquidity);

        uint256 amountETHRiskFreeValue = amountETH.mul(RiskFreeValue).div(totalETHFee);
        console.log("amountETHRiskFreeValue", amountETHRiskFreeValue );
        uint256 amountETHTreasury = amountETH.mul(Treasury).div(
            totalETHFee
        );
        console.log("amountETHTreasury",amountETHTreasury);
        bool success = false;

        //calculate leftover
        if(dynamicLiquidityFee == 0){
            uint256 amountETHLeft = amountETH.sub(amountETHRiskFreeValue.add(amountETHTreasury));
            console.log("amountETHLeft",amountETHLeft );
            //transfer calculated values to wallets
            (success, ) = payable(autoLiquidityReceiver).call{
                value: amountETHLeft,
                gas: 30000
            }("");
        }

        ( success, ) = payable(TreasuryReceiver).call{
            value: amountETHTreasury,
            gas: 30000
        }("");
        (success, ) = payable(RiskFreeValueReceiver).call{
            value: amountETHRiskFreeValue,
            gas: 30000
        }("");

        success = false;
        console.log("amountToLiquify", amountToLiquify);
        if (amountToLiquify > 0) {
            router.addLiquidityETH{value: amountETHLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
        }
    }

    function takeFee(address sender, address recipient, uint256 gonAmount)
        internal
        returns (uint256)
    {
        uint256 _totalFee = totalFee;
        if(recipient == pair) _totalFee = _totalFee.add(sellFee);

        uint256 feeAmount = gonAmount.mul(_totalFee).div(feeDenominator);

        _gonBalances[address(this)] = _gonBalances[address(this)].add(
            feeAmount
        );
        emit Transfer(sender, address(this), feeAmount.div(_gonsPerFragment));

        return gonAmount.sub(feeAmount);
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override
        initialDistributionLock
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(
                subtractedValue
            );
        }
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        override
        initialDistributionLock
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
            spender
        ].add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function approve(address spender, uint256 value)
        public
        override
        initialDistributionLock
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function checkFeeExempt(address _addr) external view returns (bool) {
        return _isFeeExempt[_addr];
    }

    function setInitialDistributionFinished() external onlyOwner {
        initialDistributionFinished = true;
    }

    function enableTransfer(address _addr) external onlyOwner {
        allowTransfer[_addr] = true;
    }

    function setFeeExempt(address _addr) external onlyOwner {
        _isFeeExempt[_addr] = true;
    }

    function shouldTakeFee(address from, address to) internal view returns (bool) {
        return (pair == from || pair == to) && (!_isFeeExempt[from]);
    }

    function setSwapBackSettings(
        bool _enabled,
        uint256 _num,
        uint256 _denom
    ) external onlyOwner {
        swapEnabled = _enabled;
        gonSwapThreshold = TOTAL_GONS.div(_denom).mul(_num);
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            msg.sender != pair &&
            !inSwap &&
            swapEnabled; //&&
          //  _gonBalances[address(this)] >= gonSwapThreshold;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return
            (TOTAL_GONS.sub(_gonBalances[DEAD]).sub(_gonBalances[ZERO])).div(
                _gonsPerFragment
            );
    }

    function setTargetLiquidity(uint256 target, uint256 accuracy) external onlyOwner {
        targetLiquidity = target;
        targetLiquidityDenominator = accuracy;
    }

    function addRebaser(address account) public onlyOwner {
        _addRebaser(account);
    }

    function removeRebaser(address account) public onlyOwner {
        _removeRebaser(account);
    }

    function isNotInSwap() external view returns (bool) {
        return !inSwap;
    }

    function sendPresale(address[] calldata recipients, uint256[] calldata values)
        external
        onlyOwner
    {
      for (uint256 i = 0; i < recipients.length; i++) {
        _transferFrom(msg.sender, recipients[i], values[i]);
      }
    }

    function checkSwapThreshold() external view returns (uint256) {
        return gonSwapThreshold.div(_gonsPerFragment);
    }

    function manualSync() external {
        InterfaceLP(pair).sync();
    }

    function setFeeReceivers(
        address _autoLiquidityReceiver,
        address _TreasuryReceiver,
        address _RiskFreeValueReceiver
    ) external onlyOwner {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        TreasuryReceiver = _TreasuryReceiver;
        RiskFreeValueReceiver = _RiskFreeValueReceiver;
    }

    function setFees(
        uint256 _liquidityFee,
        uint256 _RiskFreeValue,
        uint256 _Treasury,
        uint256 _sellFee,
        uint256 _feeDenominator
    ) external onlyOwner {
        require(_sellFee <= MAX_SELL_FEE, "sellFee limit is 5%");
        liquidityFee = _liquidityFee;
        RiskFreeValue = _RiskFreeValue;
        Treasury = _Treasury;
        sellFee = _sellFee;
        totalFee = liquidityFee.add(Treasury).add(RiskFreeValue);
        require(totalFee <= MAX_TOTAL_FEE, "totalFee limit is 18%");
        feeDenominator = _feeDenominator;
        require(totalFee < feeDenominator / 4);
    }

    function clearStuckBalance(uint256 amountPercentage, address adr) external onlyOwner {
        uint256 amountETH = address(this).balance;
        payable(adr).transfer(
            (amountETH * amountPercentage) / 100
        );
    }

    function transferToAddressETH(address payable recipient, uint256 amount)
        private
    {
        recipient.transfer(amount);
    }

    function getLiquidityBacking(uint256 accuracy)
        public
        view
        returns (uint256)
    {
        uint256 liquidityBalance = _gonBalances[pair].div(_gonsPerFragment);
        return
            accuracy.mul(liquidityBalance.mul(2)).div(getCirculatingSupply());
    }
    
    function isOverLiquified(uint256 target, uint256 accuracy)
        public
        view
        returns (bool)
    {
        return getLiquidityBacking(accuracy) > target;
    }

    receive() external payable {}
}