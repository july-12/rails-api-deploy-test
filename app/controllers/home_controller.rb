class HomeController < ApplicationController
  def index
    render json: { hello: 'world2' }
  end

end
