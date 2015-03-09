module Shop

  module WeixinHelper


    #通过微信标识获取用户身份
    def get_weixin_customer(customer=nil)
      @app_id = @site.account.app_id  if  @site.account_id
      @app_secret = @site.account.app_secret if  @site.account_id
      @app_id = Rails.configuration.weixin_app_id  if @app_id.nil?
      @app_secret = Rails.configuration.weixin_app_secret  if @app_secret.nil?

      session_key = "openid"
      session_key = @openid_key unless @openid_key.blank? #兼容微站多个站点共用组件      
      if @weixin_user.nil? && session[session_key].blank? #@weixin_user由微站框架提供，其他应用无此对象
          #render text:'请在微信中访问'
          #开发环境使用默认openid，避免跳入微信环境 o6hyyjlRoyQelo6YgWstsRJjSBb8
          if Rails.env == 'development' 
             params[:openid] = 'oLJPFuPaNInbz4s8486pxoRiTSqk' if params[:openid].blank?
             logger.info("use default openid:" + params[:openid] + " for development")
          end
          set_session_openid(session_key,@app_id,@app_secret)
          return if performed?
      end
      logger.debug("@weixin_user:" + @weixin_user.to_s)
      openid = session[session_key] unless session[session_key].blank?
      openid = @weixin_user.openid if @weixin_user   #微站获取的数据   

      if customer && customer.openid != openid #已登录用户的openid与接口获取的不一致
        customer.openid = openid
        customer.save(validate: false)
      end
      
      customer = Shop::Customer.where(openid:openid).take if customer.nil?
      if customer.nil?
        customer = Shop::Customer.new
        customer.account_id = @site.account_id if @site.has_attribute?(:account_id)        
        customer.openid = openid
        if @weixin_user      
          customer.name = @weixin_user.nickname
          customer.headimgurl = @weixin_user.headimgurl_size
        else
           weixin_userinfo = Utils::Weixin.get_userinfo(openid,@app_id,@app_secret)     
           customer.name = weixin_userinfo["nickname"] if weixin_userinfo["nickname"]
           customer.headimgurl = weixin_userinfo["headimgurl"]  if weixin_userinfo["headimgurl"]   
        end        
        customer.save(validate: false)
        #logger.debug("customer.error:" + customer.errors.full_messages)
        if customer.name.nil?
           customer.name = '微购网友' + (10000000 + customer.id.to_i).to_s 
           customer.save(validate: false)
        end
      end
      return customer
    end

  end
end
