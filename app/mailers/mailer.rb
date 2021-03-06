class Mailer < ActionMailer::Base
  #default from: "from@example.com"

  def get_delivery_options
     delivery_options = { user_name: Rails.configuration.email_user,
                         password: Rails.configuration.email_password,
                         address: Rails.configuration.email_ip,
                         port: Rails.configuration.email_port,
                         authentication: Rails.configuration.email_auth.intern,
                         enable_starttls_auto: false}
  end
  def register_email(customer)    
    @customer = customer
    from = Rails.configuration.email_user
    #logger.debug("sender_name:" + @spread_message.sender_name.to_quoted_printable)

    mail(from: from,to: customer.email, subject: '您已成功注册成为{site_name}网站会员',
    	delivery_method_options: get_delivery_options)
  end

  def forgot_pwd_email(customer)
    @customer = customer
    from = Rails.configuration.email_user
    #logger.debug("sender_name:" + @spread_message.sender_name.to_quoted_printable)

    ActionMailer::Base.raise_delivery_errors = true
    mail(from: from,to: customer.email, subject: '您在{site_name}网站申请找回密码',
      delivery_method_options: get_delivery_options)
  end

  def order_email(order,url_prefix)    
    @shop_order = order
    @url_prefix = url_prefix
    from = Rails.configuration.email_user
    #logger.debug("sender_name:" + @spread_message.sender_name.to_quoted_printable)

    mail(from: from,to: order.customer.email, subject: '您在{site_name}网站下的订单',
      delivery_method_options: get_delivery_options)
  end  

  def order_notice_sales(order)
    @shop_order = order
    from = Rails.configuration.email_user
    to = Rails.configuration.email_of_sales
    #logger.debug("sender_name:" + @spread_message.sender_name.to_quoted_printable)
    mail(from: from,to: to, subject: '网站有新订单，请及时处理',
      delivery_method_options: get_delivery_options)    
  end
  def order_notice_customer(order)
    @shop_order = order
    from = Rails.configuration.email_user
    #logger.debug("sender_name:" + @spread_message.sender_name.to_quoted_printable)
    mail(from: from,to: order.customer.email, subject: '您在{site_name}网站下单成功',
      delivery_method_options: get_delivery_options)  
  end
end