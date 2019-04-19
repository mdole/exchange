require_relative 'config/application'
require 'graphql/rake_task'
require 'coveralls/rake/task'
require 'prettier/rake/task'

Rails.application.load_tasks
Coveralls::RakeTask.new

GraphQL::RakeTask.new(schema_name: 'ExchangeSchema', idl_outfile: '_schema.graphql')

if %w[development test].include? Rails.env
  Rake::Task[:default].clear
  task default: %i[graphql:schema:diff_check spec coveralls:push]
end

Prettier::Rake::Task.new do |t|
  t.source_files = '{app,config,lib,spec}/**/*.rb'
end
