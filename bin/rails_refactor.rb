#!/usr/bin/env ruby
require 'active_support/inflector'
require 'active_support/core_ext/string/inflections'

begin
  File.exist? './config/environment.rb'
rescue LoadError
  puts "*** rails_refactor needs to be run from the root of a Rails 4 webapp ***"
  exit
end

class Renamer
  def initialize(from, to)
    @from, @to = from, to
  end

  def model_rename
    to_model_file = @to.underscore + ".rb"
    `mv app/models/#{@from.underscore}.rb app/models/#{to_model_file}`
    replace_in_file("app/models/#{to_model_file}", @from, @to)

    if File.exist?("spec/models/#{@from.underscore}_spec.rb")
      to_spec_file = @to.underscore + "_spec.rb"
      File.rename("spec/models/#{@from.underscore}_spec.rb", "spec/models/#{to_spec_file}")
      replace_in_file("spec/models/#{to_spec_file}", @from, @to)
    end
    if File.exist?("test/models/#{@from.underscore}_test.rb")
      to_test_file = @to.underscore + "_test.rb"
      File.rename("test/models/#{@from.underscore}_test.rb", "test/models/#{to_test_file}")
      replace_in_file("test/models/#{to_test_file}", @from, @to)
    end
    if File.exist?("test/fixtures/#{@from.pluralize.underscore}.yml")
      File.rename("test/fixtures/#{@from.pluralize.underscore}.yml", "test/fixtures/#{@to.pluralize.underscore}.yml")
    end
  end

  def controller_rename
    setup_for_controller_rename

    to_controller_path = "app/controllers/#{@to.underscore}.rb"
    to_resource_name   = @to.gsub(/Controller$/, "")
    to_resource_path   = to_resource_name.underscore

    `mv app/controllers/#{@from.underscore}.rb #{to_controller_path}`
    replace_in_file(to_controller_path, @from, @to)
    replace_in_file(to_controller_path, @from_resource_name.underscore, to_resource_name.underscore)
    replace_in_file(to_controller_path, @from_resource_name.singularize.underscore, to_resource_name.singularize.underscore)
    replace_in_file(to_controller_path, @from_resource_name.singularize, to_resource_name.singularize)

    if File.exist?("spec/controllers/#{@from.underscore}_spec.rb")
      to_spec = "spec/controllers/#{to_resource_path}_controller_spec.rb"
      File.rename("spec/controllers/#{@from.underscore}_spec.rb","#{to_spec}")
      replace_in_file(to_spec, @from, @to)
    end

    if File.exist?("test/controllers/#{@from.underscore}_test.rb")
      to_test = "test/controllers/#{to_resource_path}_controller_test.rb"
      File.rename("test/controllers/#{@from.underscore}_test.rb","#{to_test}")
      replace_in_file(to_test, @from, @to)
      replace_in_file(to_test, @from_resource_name.underscore, to_resource_name.underscore)
      replace_in_file(to_test, @from_resource_name.singularize.underscore, to_resource_name.singularize.underscore)
    end

    if Dir.exist?("app/views/#{@from_resource_path}")
      File.rename("app/views/#{@from_resource_path}","app/views/#{to_resource_path}")
      dir = "app/views/#{to_resource_path}"
      puts "processing dir #{dir}"
      Dir.entries(dir).select { |f| File.file?(File.join(dir, f)) }.each do |view_file|
        puts "processing view file #{view_file}"
        puts "@from.pluralize.underscore: #{@from.underscore}"
        replace_in_file("#{dir}/#{view_file}", @from_resource_name.underscore, to_resource_name.underscore)
        replace_in_file("#{dir}/#{view_file}", @from_resource_name.singularize.underscore, to_resource_name.singularize.underscore)
      end
    end

    to_helper_path = "app/helpers/#{to_resource_path}_helper.rb"
    if File.exist?("app/helpers/#{@from_resource_path}_helper.rb")
      `mv app/helpers/#{@from_resource_path}_helper.rb #{to_helper_path}`
      replace_in_file(to_helper_path, @from_resource_name, to_resource_name)
    end

    replace_in_file('config/routes.rb', @from_resource_path, to_resource_path)
  end

  def controller_action_rename
    setup_for_controller_rename
    controller_path = "app/controllers/#{@from_controller.underscore}.rb"
    replace_in_file(controller_path, @from_action, @to)

    views_for_action = "app/views/#{@from_resource_path}/#{@from_action}.*"

    Dir[views_for_action].each do |file|
      extension = file.split('.')[1..2].join('.')
      `mv #{file} app/views/#{@from_resource_path}/#{@to}.#{extension}`
    end
  end

  def setup_for_controller_rename
    @from_controller, @from_action = @from.split(".")
    @from_resource_name = @from_controller.gsub(/Controller$/, "")
    @from_resource_path = @from_resource_name.underscore
  end

  def replace_in_file(path, find, replace)
    contents = File.read(path)
    contents.gsub!(find, replace)
    File.open(path, "w+") { |f| f.write(contents) }
  end

end

if ARGV.length == 3
  command, from, to = ARGV
  renamer = Renamer.new(from, to)

  if command == "rename"
    if from.include? "Controller"
      if from.include? '.'
        renamer.controller_action_rename
      else
        renamer.controller_rename
      end
    else
      renamer.model_rename
    end
  end
elsif ARGV[0] == "test"
  require "minitest/autorun"
  class RailsRefactorTest < Minitest::Test

    def setup
      raise "Run tests in 'dummy' rails project" if !Dir.pwd.end_with? "dummy"
    end

    def teardown
      `git checkout .`
      `git clean -f`
      `rm -rf app/views/hello_worlds`
    end

    def rename(from, to)
      `../bin/rails_refactor.rb rename #{from} #{to}`
    end

    def assert_file_changed(path, from, to)
      contents = File.read(path)
      assert contents.include?(to)
      assert !contents.include?(from)
    end

    def test_model_rename
      rename("DummyModel", "NewModel")

      assert File.exist?("app/models/new_model.rb")
      assert !File.exist?("app/models/dummy_model.rb")
      assert_file_changed("app/models/new_model.rb",
                          "DummyModel", "NewModel")

      assert File.exist?("spec/models/new_model_spec.rb")
      assert !File.exist?("spec/models/dummy_model_spec.rb")
      assert_file_changed("spec/models/new_model_spec.rb",
                          "DummyModel", "NewModel")
      assert File.exist?("test/models/new_model_test.rb")
      assert !File.exist?("test/models/dummy_model_test.rb")
      assert_file_changed("test/models/new_model_test.rb",
                          "DummyModel", "NewModel")
      assert File.exist?("test/fixtures/new_models.yml")
      assert !File.exist?("test/fixtures/dummy_models.yml")
    end

    def test_controller_action_rename
      rename('DummiesController.index', 'new_action')
      assert_file_changed("app/controllers/dummies_controller.rb", "index", "new_action")
      assert File.exists?("app/views/dummies/new_action.html.erb")
      assert !File.exists?("app/views/dummies/index.html.erb")
    end

    def test_controller_rename
      rename("DummiesController", "HelloWorldsController")
      assert File.exist?("app/controllers/hello_worlds_controller.rb")
      assert !File.exist?("app/controllers/dummies_controller.rb")

      assert File.exist?("app/views/hello_worlds/index.html.erb")
      assert !File.exist?("app/views/dummies/index.html.erb")
      assert_file_changed("app/views/hello_worlds/index.html.erb",
                          "dummy", "hello_worlds")
      assert File.exist?("app/views/hello_worlds/show.html.erb")
      assert !File.exist?("app/views/dummies/show.html.erb")
      assert_file_changed("app/views/hello_worlds/show.html.erb",
                          "dummy", "hello_worlds")

      assert_file_changed("app/controllers/hello_worlds_controller.rb",
                          "DummiesController", "HelloWorldsController")
      assert_file_changed("app/controllers/hello_worlds_controller.rb",
                          "dummies", "hello_worlds")
      assert_file_changed("app/controllers/hello_worlds_controller.rb",
                          "dummy", "hello_worlds")

      routes_contents = File.read("config/routes.rb")
      assert routes_contents.include?("hello_worlds")
      assert !routes_contents.include?("dummies")

      helper_contents = File.read("app/helpers/hello_worlds_helper.rb")
      assert helper_contents.include?("HelloWorldsHelper")
      assert !helper_contents.include?("DummiesHelper")

      assert File.exist?("spec/controllers/hello_worlds_controller_spec.rb")
      assert !File.exist?("spec/controllers/dummies_controller_spec.rb")
      assert_file_changed("spec/controllers/hello_worlds_controller_spec.rb",
                          "DummiesController", "HelloWorldsController")
      assert File.exist?("test/controllers/hello_worlds_controller_test.rb")
      assert !File.exist?("test/controllers/dummies_controller_test.rb")
      assert_file_changed("test/controllers/hello_worlds_controller_test.rb",
                          "DummiesController", "HelloWorldsController")
    end
  end
else
  puts "Usage:"
  puts "  rails_refactor rename DummyController NewController"
  puts "  rails_refactor rename DummyController.my_action new_action"
  puts "  rails_refactor rename DummyModel NewModel"
end
