class Shop::ProductsController < ApplicationController
  before_action :set_shop_product, only: [:show, :edit, :update, :destroy,:add_relation]
  before_action :set_shop_categories, only: [:index,:new,:edit,:create,:update]
  before_action :set_shop_properties, only: [:new,:edit,:create,:update]
  before_action :set_shop_tags, only: [:new,:edit,:create,:update]
  before_action :init_tag_ids, only: [:create, :update]

  after_action  :update_sku_price, only: [:update] #排在前面的后执行 
  after_action  :create_product_sku, only: [:create,:update] #排在前面的后执行 
  after_action  :save_product_properties, only: [:create,:update]


  # GET /shop/products
  def index
    
    search_params_in_session

    where = "1"
    where += " AND code like '%#{params[:code].upcase}%'" unless params[:code].blank?
    where += " AND name like '%#{params[:name]}%'" unless params[:name].blank?
    where += " AND category_id = #{params[:category_id]} " unless params[:category_id].blank?

    @shop_products = Shop::Product.where(account_id: session[:account_id]).where(where).
                                   order("the_order ASC,id DESC").page(params[:page])
  end

  def search_params_in_session
    session[:shop_product_code] = params[:code] unless params[:code].nil?
    session[:shop_product_name] = params[:name] unless params[:name].nil?
    session[:shop_product_category_id] = params[:category_id] unless params[:category_id].nil?

    params[:code] = session[:shop_product_code] 
    params[:name] = session[:shop_product_name]
    params[:category_id] = session[:shop_product_category_id]
  end

  # GET /shop/products/1
  def show
  end

  # GET /shop/products/new
  def new
    @shop_product = Shop::Product.new
    @shop_product.the_order = 100
    @shop_product.tag_order = 100    
    @shop_product.price = 0        
    @shop_product.quantity = 0
    @shop_product.transport_fee = 0    
    @shop_product.discount = 100
    @shop_product.is_recommend = false
    @shop_product.is_enabled = true
    @shop_product.category_id = params[:category_id] if params[:category_id]
    params["auto_create_sku"] = true
  end

  # GET /shop/products/1/edit
  def edit
    @shop_product.category_id = params[:category_id] if params[:category_id]
    params["auto_create_sku"] = false
    params["udpate_sku_price"] = false
  end

  # POST /shop/products
  def create
    @shop_product = Shop::Product.new(shop_product_params)
    @shop_product.account_id = session[:account_id]
    @shop_product.transport_fee = 0  if @shop_product.transport_fee.nil?
    @shop_product.discount = 100 if @shop_product.discount.nil?
    if check_required_properties && @shop_product.save
      redirect_to @shop_product, notice: '产品已创建.'
    else
      render action: 'new'
    end
  end

  # PATCH/PUT /shop/products/1
  def update
    if check_required_properties && @shop_product.update(shop_product_params)
      redirect_to @shop_product, notice: '产品已更新.'
    else
      render action: 'edit'
    end
  end

  # DELETE /shop/products/1
  def destroy
    #有订单、一元产品关联，不可删除
    if Shop::OrderItem.where(product:@shop_product).count > 0
      redirect_to shop.products_url, error: '该产品有关联订单，不可删除.'
    end
    if Shop::OneProduct.where(product:@shop_product).count > 0
      redirect_to shop.products_url, error: '该产品有关联微购产品，不可删除.'
    end  
    #删除被相关的记录
    Shop::ProductRelation.where(relation_product:@shop_product).each do |relation|
      relation.destroy
    end
    @shop_product.pictures.each do |picture|
        Utils::FileUtil.delete_file(picture.path) if !picture.path.blank?
    end   
    @shop_product.destroy
    redirect_to shop.products_url, notice: '产品已删除.'
  end

  def add_relation
    proudct_codes = []
    proudct_codes = params[:proudct_codes].split(",") if params[:proudct_codes]
    proudct_codes.each do |code|
       code.upcase!
       product = Shop::Product.where(code:code).take
       if product
          product_relation = Shop::ProductRelation.new
          product_relation.product = @shop_product
          product_relation.relation_product = product
          product_relation.the_order = 10
          product_relation.save
       else
          flash[:error] = '未找到产品编码:' + code + ",不能添加相关产品"
       end
    end
    redirect_to @shop_product, notice: '相关产品已添加.' 
  end
  def del_relation
       product_relation = Shop::ProductRelation.find(params[:id])
       product = product_relation.product
       product_relation.destroy
       redirect_to product, notice: '相关产品已删除.'    
  end  

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_shop_product
      @shop_product = Shop::Product.find(params[:id])
    end
    def set_shop_categories
      @shop_categories = Shop::Category.where(account_id: session[:account_id]).order(the_order: :asc)
    end
    def set_shop_tags
      @shop_tags = Shop::Tag.where(account_id: session[:account_id]).order(the_order: :asc)
    end

    def init_tag_ids 
      params[:product][:tag_ids] ||= [] 
    end
    #设置可用属性集合
    def set_shop_properties
        category_id = 0
        category_id = @shop_product.category_id  if @shop_product
        category_id = params[:category_id] if params[:category_id]       
        category_id = params[:product][:category_id] if params[:product]
        if category_id == 0
          category_id = @shop_categories.take.id if @shop_categories.size > 0
        end
        @shop_properties = Shop::Property.where("category_id = " + category_id.to_s +
                 " OR category_id IS NULL").where(is_enabled:true).order(the_order: :asc)      
    end
    
    #检查必填属性
    def check_required_properties
        ret = true
        @shop_properties.each do |property|
          field_name = "property_" + property.id.to_s
          if property.is_required && params[field_name].blank?
            flash[:error] = property.name + "为必填项"
            ret = false          
            break
          end
        end
        return ret
    end

    #保存产品属性值
    def save_product_properties
      product_properies = []
      @shop_properties.each do |property|
        field_name = "property_" + property.id.to_s
        property_values = []
        if property.is_multiple
          #多选值
          property_values = params[field_name] if params[field_name]
        else
          property_values.push(params[field_name]) if params[field_name]
        end
        property_values.each do |value|
          #遍历多个属性值
          product_property = Shop::ProductProperty.new
          product_property.property = property
          if property.data_type == 'E' #枚举值
              product_property.property_value_id = value          
          else
            product_property.input_value = value 
          end
          product_properies.push(product_property)
        end
      end
      @shop_product.product_properties = product_properies
      @shop_product.save
    end

    #更新sku价格
    def update_sku_price
      if params[:update_sku_price]
        @shop_product.product_skus.each do |sku|
          sku.price = @shop_product.price
          sku.save
        end
      end
    end

    #自动创建产品SKU记录
    def create_product_sku
      if params["auto_create_sku"]            
        sku_properties = Shop::Property.where("category_id = " + @shop_product.category_id.to_s +
            " OR category_id IS NULL").where(is_sku:true,is_enabled:true).order(the_order: :asc)
        product_sku_properties = []
        index = 0
        get_product_properties(sku_properties,product_sku_properties,index)
      end
    end
    #通过递归对各个SKU属性进行组合,生成SKU记录
    def get_product_properties(sku_properties,product_sku_properties,index)
      sku_properties.each_with_index do |property,i| 
        logger.debug("i:" + i.to_s + ",index:" + index.to_s)
        next if i < index # 跳过已经遍历过的属性
        @shop_product.product_properties.where(property:property).each do |product_property|
          #创建SKU属性
          product_sku_property = Shop::ProductSkuProperty.new               
          product_sku_property.property = product_property.property
          product_sku_property.property_value = product_property.property_value
          product_sku_properties.push(product_sku_property)  #装载产品属性    
          #递归下一属性
          if i + 1 < sku_properties.size
            get_product_properties(sku_properties,product_sku_properties,i+1) 
          else
            #最后一层
            # SKU产品属性数目等于SKU属性才创建SKU记录
            next if product_sku_properties.size < sku_properties.size
            #SKU编码组成部分
            properties_code = "" 
            product_sku_properties.each do |product_sku_property|
              properties_code += "-" + product_sku_property.property_value.code
            end
            #TODO 如果创建过就不再创建（当前是用code控制，不可靠）
            #创建SKU记录
            product_sku = Shop::ProductSku.new
            product_sku.product_id = @shop_product.id
            product_sku.code = @shop_product.code + properties_code
            product_sku.price = @shop_product.price
            product_sku.quantity = @shop_product.quantity
            product_sku.is_enabled = true
            product_sku.save # 先保存，否则设置关联属性时，会导致保存失败
            product_sku.product_sku_properties = product_sku_properties
            product_sku.save
            logger.debug("product_sku is created.")
          end
          product_sku_properties.pop # 丢弃已使用过的产品属性          
        end
      end
    end
    # Only allow a trusted parameter "white list" through.
    def shop_product_params
      params.require(:product).permit(:name, :code, :category_id, :price_yuan, :discount, 
                                      :transport_fee_yuan,:quantity, :description,:the_order,
                                      :tag_order,:is_recommend,:is_enabled,{:tag_ids => []})
    end
end
