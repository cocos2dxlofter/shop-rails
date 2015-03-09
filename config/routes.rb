Shop::Engine.routes.draw do

  resources :logistics

  resources :delivery_items

  resources :deliveries

    resources :district_transports
    get "district_transports/get_price/:id",to: "district_transports#get_price"

    resources :one_orders
    resources :one_products
    post "one_products/delivery/:id",to: "one_products#delivery",as: "one_products_delivery"

    resources :customer_types
    resources :customers
    get "customers/get_districts/:id",to: "customers#get_districts"
    get "customers/register_check/:value",to: "customers#register_check"
    post "customers/send_verify_code",to: "customers#send_verify_code"
    

    resources :tags
    resources :product_skus
    resources :product_properties
    resources :property_values
    resources :properties

    post "orders/add_to_cart"
    post "orders/create_order"
    post "orders/alipay_notify"
    get "orders/empty_cart"
    get "orders/remove_from_cart/:id",to: "orders#remove_from_cart"
    get "orders/change_product_quantity/:id",to: "orders#change_product_quantity"
    post "orders/delivery/:id",to: "orders#delivery",as: 'order_delivery'
    get "orders/print/:id" , to: "orders#print", as: 'order_print'
    get "orders/email/:id" , to: "orders#email", as: 'order_email'
    post "orders/paid/:id" , to: "orders#paid", as: 'order_paid'    
    get "orders/promotion/:id" , to: "orders#promotion", as: 'order_promotion'    

    get "pictures/set_cover_picture/:id" , to: "pictures#set_cover_picture", as: 'pictures_set_cover_picture'
    get "products/add_relation/:id" , to: "products#add_relation", as: 'products_add_relation'
    delete "products/del_relation/:id" , to: "products#del_relation", as: 'products_del_relation'
    resources :order_items
    resources :orders
    resources :pictures
    resources :products
    resources :categories
end
