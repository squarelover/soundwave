require 'rubygems' 
require 'bundler/setup'
require 'faraday'
require 'json'
require 'pp'
require 'osc-ruby'

METRICS_URL = ENV['METRICS_UL']

TOKEN = ENV["METRICS_TOKEN"]

OSC_CLIENT_ADDRESS = 'localhost'
OSC_CLIENT_PORT = 7400

MINUTE = 60
HOUR = MINUTE * 60

class Instrument
  attr_accessor :wave, :pitch, :trigger, :envelope, :filter, :name
  ATTRIBUTES = [:wave, :pitch, :trigger, :envelope, :filter]

  def initialize(name, options={})
    @name = name
    @osc_client = OSC::Client.new( OSC_CLIENT_ADDRESS, OSC_CLIENT_PORT )
    options.each {|key,value| instance_variable_set("@#{key}", value) }

  end

  def play
    send_sound(generate)
  end

  def generate
    ATTRIBUTES.reduce({}) do |hash, attribute|
      query = self.send(attribute)
      hash[attribute] = query.execute unless query.nil?
      hash
    end
  end

  def send_sound(sound_data)
    ATTRIBUTES.each do |attribute|
      sequence = sound_data[attribute]
      @osc_client.send( OSC::Message.new( "/#{name}/#{attribute}" , *sequence)) unless sequence.nil?
    end
  end
end

class WaveFront
  attr_accessor :base_url, :connection, :token

  def initialize(base_url, token)
    @base_url = base_url
    @token = token
    @connection ||= Faraday.new(:url => base_url) do |faraday|
      faraday.response :logger                  # log requests to STDOUT
      faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
    end
  end

  def self.connection(base_url, token)
    @connection ||= new(base_url, token)
  end

end

class Query
  attr_accessor :name, :query, :time_range, :grain, :max_samples, :wavefront
  def initialize(options={})
    options = {grain: 's', name: 'soundwave', max_samples: 512}.merge(options)
    options.each {|key,value| instance_variable_set("@#{key}", value) }
  end

  def execute
    response = wavefront.connection.get do |req|
      req.url '/chart/api', t: wavefront.token
      req.params['n'] = name
      req.params['q'] = query

      delayed_time = Time.now.to_i - (time_range + (10*MINUTE))
      req.params['s'] = delayed_time.to_s
      req.params['e'] = (delayed_time + time_range).to_s
      req.params['g'] = grain
      req.headers['Content-Type'] = 'application/json'
    end

    data = JSON.parse(response.body)
    sequence = data['timeseries'][0]["data"].map {|block| block[1]}

    puts "original sequence.size => #{sequence.size}" 
    sequence = sequence[0,max_samples]
    puts "trimmed sequence.size => #{sequence.size}" 

    sequence
  end
end





wavefront = WaveFront.connection(METRICS_URL, TOKEN)

feedie_lead = Instrument.new('feedie_lead', 
  wave: Query.new(
            query: 'mavg(20,sin(mmin(30,ts(sum,some_data))))',
            time_range: (9*HOUR),
            grain: 'm',
            max_samples: 512,
            wavefront: wavefront),
  pitch: Query.new(
            query: 'ts(sum,some_other_data)',
            time_range: (16*MINUTE),
            grain: 'm',
            max_samples: 16,
            wavefront: wavefront)
)


loop do

  feedie_lead.play


  sleep(1)
end

