class Shop::OrdersController < ApplicationController
  before_action :set_shop_order, only: [:delivery,:show, :edit, :update, :destroy,
                                        :paid,:print,:email,:promotion]
  skip_before_filter :authorize,:verify_authenticity_token, only: [:add_to_cart,
                     :remove_from_cart,:empty_cart,:change_product_quantity,:alipay_notify]
  layout  false, only: [:add_to_cart,:remove_from_cart,:empty_cart,
                        :change_product_quantity,:alipay_notify,:print]

  #加入购物车
  #property_no=1 表示不要求指定sku属性
  def add_to_cart
    if request.post? && params[:product_id] && (params[:property_value] || params[:property_no])
       @cart = session[:cart] ||= Shop::Cart.new
       
       product = Shop::Product.find(params[:product_id]) if params[:property_no]

       #TODO 支持多个属性选sku
       product_sku = Shop::ProductSku.joins(:product_sku_properties).
                      where(product_id:params[:product_id],
                            :shop_product_sku_properties => {property_value_id:params[:property_value]}).
                            take if params[:property_value]
      if (product_sku && product_sku.price.to_i > 0) || params[:property_no]
        quantity = params[:quantity].to_i if params[:quantity]
        quantity = 1 if quantity < 1
        @cart.add_product_sku(product,product_sku,quantity)
        render json: {is_success:"true",message:"添加成功",cart_item_count:@cart.items.size}
      else
        #商品不存存或已下架
        render json: {is_success:"false",message:"商品不存在或已下架"}
      end
    else
       render json: {is_success:"false",message:"参数不全"}
    end
  end

  #改变购物车中商品数量
  def change_product_quantity
    @cart = session[:cart] ||= Shop::Cart.new
    product = Shop::Product.find(params[:id]) if params[:property_no]
    product_sku = Shop::ProductSku.find(params[:id]) unless params[:property_no]
    if product_sku || product
       @cart.change_product_sku(product,product_sku,params[:quantity])
    end
    render json: {is_success:"true",message:"已从购物车移出商品" }
  end

  #从购物车移出商品
  def remove_from_cart
    @cart = session[:cart] ||= Shop::Cart.new
    product = Shop::Product.find(params[:id]) if params[:property_no]
    product_sku = Shop::ProductSku.find(params[:id]) unless params[:property_no]
    if product_sku || product
       @cart.remove_product_sku(product,product_sku)
    end
    render json: {is_success:"true",message:"已从购物车移出商品" }
  end

  #清空购物车
  def empty_cart
    session[:cart] = nil
    render json: {is_success:"true",message:"购物车已清空" }
  end

  #接收支付宝支付结果通知
  def alipay_notify

    account_id = nil
    if !params[:site_key].blank? #兼容微站
       site = Site::Site.find_by_site_key(params[:site_key])
       account_id = site.account_id
    end

     notify_params = params.except(*request.path_parameters.keys)
   # 先校验消息的真实性
    if Alipay::Sign.verify?(notify_params) && Alipay::Notify.verify?(notify_params)
      # 获取交易关联的订单
      order = Shop::Order.where(order_no:params[:out_trade_no],
                                 account_id: account_id,is_paid:false).take
      logger.error("can't find unpaid order_no:" + params[:out_trade_no]) unless order
      logger.info("order_no:" + params[:out_trade_no] + " trade_status:" + params[:trade_status])
      case params[:trade_status]
      when 'WAIT_BUYER_PAY'
        # 交易开启
      when 'WAIT_SELLER_SEND_GOODS'
        # 买家完成支付,等发货
      when 'TRADE_SUCCESS'
        # 交易完成(直接收款)
        order.is_paid = true if order
      when 'TRADE_FINISHED'
        # 交易成功并且完成
        order.is_paid = true if order
      when 'TRADE_CLOSED'
        # 交易被关闭
      end
      order.pay_way = 'alipay'
      order.trade_no = params[:trade_no] if order
      order.paid_date = Time.now if order
      order.save if order

      render :text => 'success' # 成功接收消息后，需要返回纯文本的 ‘success’，否则支付宝会定时重发消息，最多重试7次。 
    else
      render :text => 'error'
    end
  end

  #微信支付结果通知
  def weixin_notify
    #转换xml内容数据为params[:xml]数组，需在config/application.rb中配置
    # config.middleware.insert_after ActionDispatch::ParamsParser, ActionDispatch::XmlParamsParser    

    account_id = nil
    if !params[:site_key].blank? #兼容微站
       site = Site::Site.find_by_site_key(params[:site_key])
       pay_sign_key= site.account.pay_sign_key if  site.account_id
       account_id = site.account_id
    end
     
    
    pay_sign_key= Rails.configuration.weixin_pay_sign_key  if pay_sign_key.nil?  

    xml_sign = params[:xml][:sign]
    params[:xml][:sign] = ""
    logger.debug(params[:xml])
    notify_sign = Utils::Wxpay.pay_sign(params[:xml],pay_sign_key)
    logger.debug("notify_sign:" + notify_sign)
    if notify_sign != xml_sign       
       logger.info("weixin pay notify fail: sign error or " + params[:xml].to_s) 
       logger.info("xml_sign:" + xml_sign + ",notify_sign:" + notify_sign) 
       render :text => '<xml><return_code>FAIL</return_code><return_msg>签名失败</return_msg></xml>'
       return
    end

    if params[:xml][:result_code] == 'SUCCESS'
      order = Shop::Order.where(order_no:params[:xml][:out_trade_no],
                                 account_id: account_id,is_paid:false).take
      if order.nil?
        logger.info("weixin pay notify fail: trade_no is not found: " + params[:xml].to_s)
        render :text => '<xml><return_code>FAIL</return_code><return_msg>订单不存在</return_msg></xml>'
      else
        order.pay_way = 'weixin'
        order.trade_no = params[:xml][:transaction_id] 
        order.paid_date = Time.now if order
        order.is_paid = true
        order.save
        render :text => '<xml><return_code>SUCCESS</return_code></xml>'
      end
    else
       logger.info("weixin pay notify result fail:  " + params[:xml].to_s)
       render :text => '<xml><return_code>SUCCESS</return_code></xml>'  
    end
        
  end

 #发货
  def delivery

    if @shop_order.is_delivered || !@shop_order.is_paid 
      flash[:error] = "该订单已是发货状态，不能再次发货" if @shop_order.is_delivered
      flash[:error] = "该订单还未付款，不能发货" unless @shop_order.is_paid
    else
      #选中的表单条目
      item_ids = []
      item_ids = params[:item_ids] if params[:item_ids]
      ids = '0'
      item_ids.each do |id|
        ids += "," + id.to_s
      end
      items = Shop::OrderItem.where("ID IN (" + ids + ")").where(is_delivered:false)
      if items.size == 0
        flash[:error] = '申请出货操作失败，没有选中未发货的订单条目'
        redirect_to @shop_order
        return
      end
      #生成发货单
      delivery = Shop::Delivery.new
      delivery.order = @shop_order
      delivery.logistic_id = params[:logistic_id]
      delivery.invoice_no = params[:invoice_no]
      delivery.save

      items.each do |item|
        delivery_item = Shop::DeliveryItem.new
        delivery_item.delivery = delivery
        delivery_item.product_sku_id = item.product_sku_id
        delivery_item.product_id = item.product_id
        delivery_item.quantity = item.quantity
        delivery_item.save
        
        item.is_delivered = true
        item.delivery = delivery
        item.save
      end

      #更新订单发货状态
      if @shop_order.order_items.where(is_delivered:false).size == 0
         @shop_order.is_delivered = true
         @shop_order.delivery_date = Time.now
         @shop_order.save
         flash[:notice] = "全部商品发货完成"
      else
         flash[:notice] = "部分商品发货完成"
      end
      
    end
    redirect_to @shop_order
  end

  # GET /shop/orders
  def index
    @shop_orders = Shop::Order.where(account_id: session[:account_id]).order("id DESC").page(params[:page])
  end

  # GET /shop/orders/1
  def show
    @logistics = Shop::Logistic.where(account_id: session[:account_id])
  end
  
  def print    
  end

    #收款
  def paid
    if  @shop_order.is_paid == false    
        @shop_order.is_paid = true
        @shop_order.paid_date = Time.now
        @shop_order.pay_way = params[:pay_way] unless params[:pay_way].blank?
        @shop_order.trade_no = params[:trade_no] unless params[:trade_no].blank?
        @shop_order.save
        
        @shop_order.create_promotion_points
        flash[:notice] = '已确认收款.'
    else
      flash[:error] = '确认失败，只有已下单且未收款的订单才能进行确认收款.'
    end
    redirect_to @shop_order
  end

  def email
    Mailer.order_email(@shop_order,request.host_with_port).deliver
    flash.now[:notice] = "已邮件通知客户"
    redirect_to @shop_order    
  end  

  #确认积分给客户
  def promotion
    promotion_history = Shop::PromotionHistory.where(order:@shop_order,change_type:'A').take
    if promotion_history || !@shop_order.is_paid 
      flash[:error] = "该订单已确认过积分了" if promotion_history
      flash[:error] = "该订单还未付款，不能确认积分" if !@shop_order.is_paid
    else
       customer = @shop_order.customer
       promotion_history = Shop::PromotionHistory.new
       promotion_history.order =  @shop_order
       promotion_history.change_type = 'A'
       promotion_history.change_points = @shop_order.count_promotion_points

       if promotion_history.change_points > 0         
         promotion_history.customer =  customer
         promotion_history.save

         customer.promotion_points = customer.promotion_points.to_i + promotion_history.change_points
         customer.save
         flash[:notice] = "积分确认完成"
       else
         flash[:error] = "该订单金额不足，不能确认积分"
       end
    end
    redirect_to @shop_order   
  end

  # GET /shop/orders/new
  def new
    @shop_order = Shop::Order.new
    render text: '后台不可新建订单'
  end

  # GET /shop/orders/1/edit
  def edit
    #render text: '后台不可修改订单'
  end

  # POST /shop/orders
  def create
    @shop_order = Shop::Order.new(shop_order_params)
    @shop_order.account_id = session[:account_id]
    if @shop_order.save
      redirect_to shop.orders_url, notice: '订单已创建.'
    else
      render action: 'new'
    end
  end

  # PATCH/PUT /shop/orders/1
  def update
    if @shop_order.is_paid
      flash[:error] = "订单已付款，不能修改条目" 
      redirect_to shop.orders_url      
    else    
      if @shop_order.update(shop_order_params)
        #按折扣更新产品费用、总费用
        product_fee = 0
        @shop_order.order_items.each do |item|
          item.discount = @shop_order.discount
          item.save
          product_fee += (item.price * item.quantity * item.discount / 100.0).round 
        end
        @shop_order.product_fee =  product_fee
        @shop_order.total_fee = @shop_order.product_fee  + @shop_order.transport_fee - 
                                @shop_order.promotion_fee
        @shop_order.save

        redirect_to shop.orders_url, notice: '订单已更新.'
      else
        render action: 'edit'
      end
    end
  end

  # DELETE /shop/orders/1
  def destroy
    if @shop_order.is_paid
      flash[:error] = "订单已付款，不能删除条目" 
    else 
      @shop_order.destroy
      flash[:notice] = '订单已删除.'
    end
    redirect_to shop.orders_url
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_shop_order
      @shop_order = Shop::Order.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def shop_order_params
      params.require(:order).permit(:remark, :discount, :transport_fee_yuan,
                                    :receiver_name,:receiver_mobile,:receiver_address, :receiver_zip,
                                    :require_invoice,:invoice_title,:receiver_province_id,
                                    :receiver_city_id,:receiver_area_id)
    end
end