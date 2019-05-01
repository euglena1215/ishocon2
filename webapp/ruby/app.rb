require 'sinatra/base'
require 'mysql2'
require 'mysql2-cs-bind'
require 'erubis'

require '/home/ishocon/webapp/ruby/redis_client.rb'

module Ishocon2
  class AuthenticationError < StandardError; end
  class PermissionDenied < StandardError; end
end

class Ishocon2::WebApp < Sinatra::Base
  session_secret = ENV['ISHOCON2_SESSION_SECRET'] || 'showwin_happy'
  use Rack::Session::Cookie, key: 'rack.session', secret: session_secret
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../public', __FILE__)
  set :protection, true

  helpers do
    def config
      @config ||= {
        db: {
          host: ENV['ISHOCON2_DB_HOST'] || 'localhost',
          port: ENV['ISHOCON2_DB_PORT'] && ENV['ISHOCON2_DB_PORT'].to_i,
          username: ENV['ISHOCON2_DB_USER'] || 'ishocon',
          password: ENV['ISHOCON2_DB_PASSWORD'] || 'ishocon',
          database: ENV['ISHOCON2_DB_NAME'] || 'ishocon2'
        }
      }
    end

    def db
      return Thread.current[:ishocon2_db] if Thread.current[:ishocon2_db]
      client = Mysql2::Client.new(
        host: config[:db][:host],
        port: config[:db][:port],
        username: config[:db][:username],
        password: config[:db][:password],
        database: config[:db][:database],
        reconnect: true
      )
      client.query_options.merge!(symbolize_keys: true)
      Thread.current[:ishocon2_db] = client
      client
    end

    def election_results
      query = <<~SQL
        SELECT c.id, c.name, c.political_party, c.sex
        FROM candidates AS c
      SQL
      results = db.xquery(query)
      results.each do |row|
        row[:count] = RedisClient.get_vote_count_by_candidate(row[:id])
      end

      results.to_a.sort {|a,b| (b[:count] || 0) <=> (a[:count] || 0) }
    end

    def voice_of_supporter(candidate_ids)
      query = <<SQL
SELECT keyword
FROM votes
WHERE candidate_id IN (?)
GROUP BY keyword
ORDER BY COUNT(*) DESC
LIMIT 10
SQL
      db.xquery(query, candidate_ids).map { |a| a[:keyword] }
    end

    def db_initialize
      db.query('DELETE FROM votes')
      RedisClient.reset_vote
      RedisClient.reset_votes_group_by_keyword_candidate_id
      RedisClient.reset_votes_group_by_keyword_political_party
    end
  end

  get '/' do
    candidates = []
    results = election_results
    results.each_with_index do |r, i|
      # 上位10人と最下位のみ表示
      candidates.push(r) if i < 10 || 28 < i
    end

    parties_set = db.query('SELECT DISTINCT political_party FROM candidates')
    parties = {}
    parties_set.each { |a| parties[a[:political_party]] = 0 }
    results.each do |r|
      parties[r[:political_party]] += r[:count] || 0
    end

    sex_ratio = { '男': 0, '女': 0 }
    results.each do |r|
      sex_ratio[r[:sex].to_sym] += r[:count] || 0
    end

    erb :index, locals: { candidates: candidates,
                          parties: parties,
                          sex_ratio: sex_ratio }
  end

  get '/candidates/:id' do
    candidate = db.xquery('SELECT * FROM candidates WHERE id = ?', params[:id]).first
    return redirect '/' if candidate.nil?
    votes = RedisClient.get_vote_count_by_candidate(params[:id])
    keywords = RedisClient.get_keyword_sorted_votes_count_by_candidates(params[:id])
    erb :candidate, locals: { candidate: candidate,
                              votes: votes,
                              keywords: keywords }
  end

  get '/political_parties/:name' do
    query = <<~SQL
      SELECT id
      FROM candidates AS c
      WHERE political_party = ?
    SQL
    candidate_ids = db.xquery(query, params[:name]).map { |row| row[:id] }
    votes = candidate_ids.map {|id| RedisClient.get_vote_count_by_candidate(id)}.compact.sum

    candidates = db.xquery('SELECT * FROM candidates WHERE political_party = ?', params[:name])
    candidate_ids = candidates.map { |c| c[:id] }
    keywords = RedisClient.get_keyword_sorted_votes_count_by_political_parties(params[:name])
    erb :political_party, locals: { political_party: params[:name],
                                    votes: votes,
                                    candidates: candidates,
                                    keywords: keywords }
  end

  get '/vote' do
    candidates = db.query('SELECT * FROM candidates')
    erb :vote, locals: { candidates: candidates, message: '' }
  end

  post '/vote' do
    user = db.xquery('SELECT * FROM users WHERE name = ? AND address = ? AND mynumber = ?',
                     params[:name],
                     params[:address],
                     params[:mynumber]).first
    candidate = db.xquery('SELECT * FROM candidates WHERE name = ?', params[:candidate]).first
    voted_count =
      user.nil? ? 0 : RedisClient.get_vote_count_by_user(user[:id])

    candidates = db.query('SELECT * FROM candidates')
    if user.nil?
      return erb :vote, locals: { candidates: candidates, message: '個人情報に誤りがあります' }
    elsif user[:votes] < (params[:vote_count].to_i + voted_count)
      return erb :vote, locals: { candidates: candidates, message: '投票数が上限を超えています' }
    elsif params[:candidate].nil? || params[:candidate] == ''
      return erb :vote, locals: { candidates: candidates, message: '候補者を記入してください' }
    elsif candidate.nil?
      return erb :vote, locals: { candidates: candidates, message: '候補者を正しく記入してください' }
    elsif params[:keyword].nil? || params[:keyword] == ''
      return erb :vote, locals: { candidates: candidates, message: '投票理由を記入してください' }
    end

    db.xquery("INSERT INTO votes (user_id, candidate_id, keyword) 
               VALUES #{(['(?, ?, ?)'] * params[:vote_count].to_i).join(',')}",
               *([user[:id],
               candidate[:id],
               params[:keyword]] * params[:vote_count].to_i))
    RedisClient.incr_vote(params[:vote_count].to_i, user[:id], candidate[:id], params[:keyword])
    RedisClient.incr_votes_group_by_keyword_candidate_id(candidate[:id], params[:vote_count].to_i, params[:keyword])
    RedisClient.incr_votes_group_by_keyword_political_party(candidate[:political_party], params[:vote_count].to_i, params[:keyword])
    return erb :vote, locals: { candidates: candidates, message: '投票に成功しました' }
  end

  get '/initialize' do
    db_initialize
  end
end
