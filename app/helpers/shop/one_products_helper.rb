module Shop::OneProductsHelper

  	def one  		
      @recommend_one_products = Shop::OneProduct.joins(:product).where(
                                       is_closed:false,shop_products:{is_recommend:true}).
                                       order("shop_products.the_order ASC,id DESC").limit(9)      
      @recommend_one_products = @recommend_one_products.where(account_id:@site.account_id) if @site.has_attribute?(:account_id)
  	end
  	#商品列表
  	def one_product_list

      @one_products = Shop::OneProduct.where(is_closed:false).order("id DESC").page(params[:page]).per_page(5)
      @one_products = @one_products.where(account_id:@site.account_id)  if @site.has_attribute?(:account_id)
      #logger.debug("request.format:" + request.format)                                       
      if request.format == 'application/json'
        render json: @one_products.to_json(:include => [:product => {methods: :picture_path}])
      end
  	end
  	#商品详情
  	def one_product_detail
      @one_product = Shop::OneProduct.find(params[:id])
  	end  	

    #订单提交
    def one_order_post
      if request.post?
         customer = get_customer
         if customer.nil?
            return
         end
         @one_order = Shop::OneOrder.new
         @one_order.account_id = @site.account_id if @site.has_attribute?(:account_id)
         @one_order.customer = customer
         @one_order.one_product = Shop::OneProduct.find(params[:one_product_id])
         @one_order.order_person_time = params[:order_person_time]
         @one_order.is_paid = false
         @one_order.got_code_quantity = 0
         @one_order.is_got_all_code = false
         @one_order.generate_trade_no #生成支付交易号
         @one_order.save
         if ! @one_order.persisted?
           render text:'订单创建失败，请联系网站管理员'
           logger.info("one_order_post.error" + @one_order.errors.inspect) if @one_order.errors.size > 0
           return
         end
         # @one_order.pay_success('weixin','200000000') #测试
         # pay_url /weixin/pay/start
         # return_url /cms/page/one/my_order_list

         redirect_to params[:pay_url] + "?one_order_id=" + @one_order.id.to_s + 
                                         "&site_key=" + @site.site_key + 
                                         "&return_url=" + params[:return_url]
      else
        render text:'当前访问操作不合法'  
      end
    end

    def one_weixin_pay

      @app_id = @site.account.app_id  if  @site.has_attribute?(:account_id)
      @app_secret = @site.account.app_secret if @site.has_attribute?(:account_id)
      @partner_id = @site.account.partner_id if @site.has_attribute?(:account_id)
      @partner_key = @site.account.partner_key if @site.has_attribute?(:account_id)
      @pay_sign_key= @site.account.pay_sign_key if @site.has_attribute?(:account_id)

      @app_id = Rails.configuration.weixin_app_id  if @app_id.nil?
      @app_secret = Rails.configuration.weixin_app_secret  if @app_secret.nil?
      @partner_id = Rails.configuration.weixin_partner_id  if @partner_id.nil?
      @partner_key = Rails.configuration.weixin_partner_key  if @partner_key.nil?
      @pay_sign_key= Rails.configuration.weixin_pay_sign_key  if @pay_sign_key.nil?    

      @access_token = Utils::Weixin.get_access_token(@app_id,@secert)
     
      @return_url = "/"
      @return_url = params[:return_url] unless params[:return_url].blank?

      url = request.original_url.split('?')[0]
      @notify_url = url[0,url.rindex('/')] + "/weixin_pay_notify"   

      if params[:one_order_id]
        #一元微购
        @one_order = Shop::OneOrder.find(params[:one_order_id])
        @body = @one_order.one_product.product.name + "【1元微购】" + @one_order.order_person_time.to_s + "人次"
        @total_fee = @one_order.order_person_time #* 100 #1元转换成100分
      end      
    end



 #支付结果通知
  def one_weixin_pay_notify
    
    order = Shop::OneOrder.where(trade_no:params[:out_trade_no]).take
    if order.nil?
      logger.info("weixin pay notify fail: trade_no is not found")
      render :text => 'fail' 
      return
    end

    pay_sign_key = @site.account.pay_sign_key if @site.has_attribute?(:account_id)
    pay_sign_key = Rails.configuration.weixin_pay_sign_key if pay_sign_key.nil?

    notify_sign = Utils::Weixin.pay_sign({
          :appid     => params[:xml][:AppId],
          :appkey    => pay_sign_key,
          :noncestr  => params[:xml][:NonceStr],
          :openid   => params[:xml][:OpenId],
          :issubscribe   => params[:xml][:IsSubscribe],          
          :timestamp => params[:xml][:TimeStamp]
          })
    logger.debug("notify_sign:" + notify_sign)
    if notify_sign == params[:xml][:AppSignature] && params['trade_state'] == '0' 
       order.pay_success('weixin',params[:out_trade_no])
       render :text => 'success' 
    else
      logger.info("weixin pay notify fail: sign error or trade_state is not zero") 
        render :text => 'fail'
    end
  end

  	#结果列表
  	def one_result_list
  		@one_products = Shop::OneProduct.where(is_closed:true).order("id DESC").page(params[:page]).per_page(5)
      @one_products = @one_products..where(account_id:@site.account_id) if @site.has_attribute?(:account_id)
      #logger.debug("request.format:" + request.format)                                       
      if request.format == 'application/json'
        render json: @one_products.to_json(methods: :result_time_str,
                  :include => [:product => {methods: :picture_path}] +
                              [:result_customer =>{methods: :get_headimgurl,
                                   :only =>[:id, :name]}])
      end
  	end  	

  	#结果详情
  	def one_result_detail
  		@one_product = Shop::OneProduct.find(params[:id])
  	end

    #个人订单列表
    def one_my_order_list
      @customer = get_customer
      @my_one_orders = Shop::OneOrder.where(customer_id:@customer.id,is_paid:true).
                                      order("id DESC").page(params[:page]).per_page(5) if @customer 

      if request.format == 'application/json'
        render json: @my_one_orders.to_json(methods: :pay_time_str,
            :include => [:one_product => {:include => [:product =>{methods: :picture_path}]}]) if @my_one_orders
      end                                      
    end

    #个人订单查看
    def one_my_order_view
      @customer = get_customer
      @my_one_order = Shop::OneOrder.find(params[:id])                                          
    end

    #获得的商品
    def one_my_product_list
      @customer = get_customer
      @my_one_products = Shop::OneProduct.where(result_customer_id:@customer.id).
                                          order("id DESC").page(params[:page]).per_page(2) if @customer 

      #logger.debug("request.format:" + request.format)                                       
      if request.format == 'application/json'
        render json: @my_one_products.to_json(methods: :result_time_str,
                    :include => [:product => {methods: :picture_path}]) if @my_one_products
      end
    end

    #获得商品查看及收货地址确认
    def one_my_product_view
      @customer = get_customer
      @my_one_product = Shop::OneProduct.find(params[:id]) 
      if @my_one_product.result_customer_id != @customer.id
        render text:'此商品不是您所获得，不可以查看或修改'
        return
      end
      if request.post? #确认收货地址
          #收货信息
          @my_one_product.receiver_name = params[:name]
          @my_one_product.receiver_mobile = params[:mobile]    
          @my_one_product.receiver_address = params[:address]
          @my_one_product.receiver_zip = params[:zip]    
          @my_one_product.receiver_province_id = params[:province_id]    
          @my_one_product.receiver_city_id = params[:city_id]    
          @my_one_product.receiver_area_id = params[:area_id]  
          @my_one_product.remark = params[:remark]    

          @my_one_product.receiver_is_confirmed = true
          @my_one_product.save                                              
      end                                       
    end    

    #通过微信标识获取用户身份
    def get_customer
      session_key = "openid"
      session_key = @openid_key unless @openid_key.blank? #兼容微站多个站点共用组件
      if @weixin_user.nil? && session[session_key].blank?
          #render text:'请在微信中访问'
          Utils::Weixin.set_session_openid(params,session,request.original_url,session_key)
          return 
      end

      openid = session[session_key] unless session[session_key].blank?
      openid = @weixin_user.openid if @weixin_user      

      customer = Shop::Customer.where(openid:openid).take
      if customer.nil?
        customer = Shop::Customer.new
        customer.account_id = @site.account_id if @site.has_attribute?(:account_id)        
        
        customer.openid = openid
        if @weixin_user      
          customer.name = @weixin_user.nickname
          customer.headimgurl = @weixin_user.headimgurl_size
        else
           weixin_userinfo = Utils::Weixin.get_userinfo(openid)     
           customer.name = weixin_userinfo["nickname"] if weixin_userinfo["nickname"]
           customer.headimgurl = weixin_userinfo["headimgurl"]  if weixin_userinfo["headimgurl"]   
        end

        customer.name = '微购网友' + (10000000 + customer.id).to_s if customer.name.nil?
        customer.save(validate: false)
      end
      return customer
    end

end
