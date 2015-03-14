class Shop::Product < ActiveRecord::Base
  attr_accessible :finalsale
  validates_presence_of :name,:category,:code
  validates :code,uniqueness: { scope: :account_id, message: "产品编码不可重复" }
  validates :code, format: { with: /\A[A-Z0-9\-_]+\z/,message: "编码只能是大写字母、数字、横线、下划线" }

  validates :price, numericality: { only_integer: true ,greater_than_or_equal_to: 0,message:"价格必须大于等于0"}
  validates :transport_fee, numericality: { only_integer: true ,greater_than_or_equal_to: 0,message:"运费必须大于等于0"}
  validates :quantity, numericality: { only_integer: true ,greater_than_or_equal_to: 0,message:"数量必须大于等于0"}  

  validates :discount, numericality: { only_integer: true ,greater_than_or_equal_to: 0,less_than_or_equal_to:100,message:"折扣必须大于等于0，小于等于100"}

  belongs_to :category
  belongs_to :picture
  has_many :pictures
  has_many :product_properties,dependent: :destroy
  has_many :product_skus,dependent: :destroy
  has_many :product_relations,dependent: :destroy

  has_and_belongs_to_many :tags

  before_validation :capitalize_code

  #编码自动转换成大写
  def capitalize_code
    self.code.upcase! if self.code
  end

  #SKU属性列表
  def sku_properties_list
     sku_properties = product_properties.joins(:property).where(shop_properties:{is_sku:true}).
                                         order(:property_id)
     list = ""
     last_property_id = 0
     sku_properties.each_with_index  do |sku_property,index|
       list += sku_property.property.name + ":" if last_property_id == 0 #开始属性
       if  last_property_id != 0 && last_property_id != sku_property.property.id
          #更换属性
          list.chop! #删除多余的,
          list +=";" + sku_property.property.name + ":" 
       end
       last_property_id = sku_property.property.id 

       list += sku_property.property_value.value
       list += "," if index + 1 < sku_properties.size      
     end 
     list
  end
 
  #商品体积
  def volume
    volume = 0
    diameter = depth = height = width = length = 0
    product_properties = self.product_properties.joins(:property).
                                   where("shop_properties.code like 'SIZE%'")
    product_properties.each do |product_property|
       unless product_property.input_value.to_i == 0
         case product_property.property.code
         when 'SIZE-DIAMETER'
           diameter = product_property.input_value.to_i
         when 'SIZE-DEPTH'
           depth = product_property.input_value.to_i
         when 'SIZE-HEIGHT'
           height = product_property.input_value.to_i
         when 'SIZE-WIDTH'
           width = product_property.input_value.to_i
         when 'SIZE-LENGTH'
           length = product_property.input_value.to_i
         end         
       end
    end
    logger.debug("diameter:" + diameter.to_s + ",depth:" + depth.to_s + 
                 ",height:" + height.to_s + ",width:" + width.to_s + ",length:" + length.to_s)
    if length != 0 && width != 0 && height != 0  #长宽高有值
      volume = length * width * height
    end
    if depth != 0 && width != 0 && height != 0 #深宽高有值
      volume = depth * width * height
    end
    if diameter != 0  && height != 0 #直径高有值
      r = diameter / 2.0 
      volume = (Math::PI * r * r * height).round
    end    
    logger.debug("volume:" + volume.to_s)
    volume
  end

  def price_yuan
    format("%.2f",self.price.to_i / 100.00)    
  end
  def price_yuan=(value)
    self.price = (value.to_f * 100).round
  end
  
  def finalsale_yuan
      format("%.2f",self.finalsale.to_i / 100.00)
  end
  def finalsale_yuan=(value)
      self.finalsale = (value.to_f * 100).round
  end

  def transport_fee_yuan
    format("%.2f",self.transport_fee.to_i / 100.00)    
  end  
  def transport_fee_yuan=(value)
    self.transport_fee = (value.to_f * 100).round
  end  

  def picture_path
    path = ""
    path = self.picture.path if self.picture
    return path
  end

end
