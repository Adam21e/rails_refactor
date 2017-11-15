class DummiesController < ApplicationController
  def index
    @dummies = Dummy.all
  end

  def show
    @dummy = Dummy.find params[:id]
  end
end
