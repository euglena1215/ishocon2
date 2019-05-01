require 'redis'
require 'redis/connection/hiredis'

class RedisClient
  @@redis = (Thread.current[:isu_redis] ||= Redis.new(host: '127.0.0.1', port: 6379))
  class << self

    def incr_vote(count, user_id, candidate_id, keyword)
      @@redis.incrby(key_votes(user_id, candidate_id, key_votes_keyword_mapping(keyword)), count)
    end

    def get_vote(user_id, candidate_id, keyword)
      @@redis.get(key_votes(user_id, candidate_id, key_votes_keyword_mapping(keyword))).to_i
    end

    def get_vote_count_by_candidate(candidate_id)
      keys = @@redis.keys(key_votes('*', candidate_id, '*'))
      return 0 if keys.empty?
      @@redis.mget(*keys).map(&:to_i).sum
    end

    def get_vote_count_by_user(user_id)
      keys = @@redis.keys(key_votes(user_id, '*', '*'))
      return 0 if keys.empty?
      @@redis.mget(*keys).map(&:to_i).sum
    end

    def reset_vote
      keys = @@redis.keys("isu:votes:*")
      return if keys.empty?
      @@redis.del(*keys)
    end

    def incr_votes_group_by_keyword_candidate_id(candidate_id, count, keyword)
      @@redis.zincrby(key_votes_group_by_keyword_candidate_id(candidate_id), count * (-1), key_votes_keyword_mapping(keyword))
    end

    def reset_votes_group_by_keyword_candidate_id
      keys = @@redis.keys("isu:votes_group_by_keyword_candidate_id:*")
      return if keys.empty?
      @@redis.del(*keys)
    end

    def get_keyword_sorted_votes_count_by_candidates(candidate_id)
      @@redis.zrangebyscore(key_votes_group_by_keyword_candidate_id(candidate_id), "-inf", 0, limit: [0, 10])
    end

    def incr_votes_group_by_keyword_political_party(political_party, count, keyword)
      @@redis.zincrby(key_votes_group_by_keyword_political_party(key_votes_political_party_mapping(political_party)), count * (-1), key_votes_keyword_mapping(keyword))
    end

    def reset_votes_group_by_keyword_political_party
      keys = @@redis.keys("isu:votes_group_by_keyword_political_party:*")
      return if keys.empty?
      @@redis.del(*keys)
    end

    def get_keyword_sorted_votes_count_by_political_parties(political_party)
      @@redis.zrangebyscore(key_votes_group_by_keyword_political_party(key_votes_political_party_mapping(political_party)), "-inf", 0, limit: [0, 10])
    end

    private

    def key_votes(user_id, candidate_id, keyword)
      "isu:votes:#{user_id}:#{candidate_id}:#{keyword}"
    end

    def key_votes_group_by_keyword_candidate_id(candidate_id)
      "isu:votes_group_by_keyword_candidate_id:#{candidate_id}"
    end

    def key_votes_group_by_keyword_political_party(political_party)
      "isu:votes_group_by_keyword_political_party:#{political_party}"
    end

    def key_votes_keyword_mapping(keyword)
      case keyword
      when '他にまともな候補者がいないため'
        1
      when '若手で、また、働く環境や貧困について真剣に考えてくれているように感じたから'
        2
      when '声に惹かれた'
        3
      when '私と名前が同じだったから'
        4
      when '経歴'
        5
      when '誠実さ'
        6
      when '顔が好み'
        7
      when '自分の所属する政党の候補者だったから'
        8
      when '全候補者について、学歴や経歴は見ず、政策や演説だけで判断した結果、最も自分が描いていた社会に近かったから'
        9
      when '政策を吟味した結果。あの党の政策は反対だと感じたため、そこに対抗しうる政党を選んだ'
        10
      when '誰もが人間らしく生きられる社会をめざしているため'
        11
      when '自分でもなぜか分からない'
        12
      when '教えてたくない'
        13
      when '愛に対する考え方'
        14
      when '親戚と顔が似ていたから'
        15
      when '若干極端な選択だが、この様な声があるのは悪い事ではない。他に良い立候補者がいない。個人的には、左寄りが必要。世界的に見て「ナショナリズム」が台頭しているためこの国も染まってしまう前に左寄りへ。でも極端に左なのは絶対に嫌だ'
        16
      when '気分'
        17
      when '女性の輝く社会を実現しようと公約を掲げていたため'
        18
      when '実際にお会いする機会があった際、若い世代の問題に取り組む姿勢があり、また質問に誠実に答えてくれる印象を受けたから'
        19
      when '税金を無駄遣いしてくれそうだから'
        20
      when '若いから'
        21
      when 'ノーコメント'
        22
      when '政権交代して欲しかったため'
        23
      when '一番最初に目に入った名前だったから'
        24
      else
        raise keyword
      end

    def key_votes_political_party_mapping(political_party)
      case political_party
      when '夢実現党'
        1
      when '国民10人大活躍党'
        2 
      when '国民元気党'
        3 
      when '国民平和党'
        4 
      else
        raise political_party
      end
    end
  end
end
