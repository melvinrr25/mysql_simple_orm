require 'mysql_simple_orm/version'
require 'mysql2'

module MysqlSimpleOrm
  class Base
    def initialize(attrs={})
      self.class.build_entity_methods
      
      cols = self.class.fetch_columns.select{|c| c.to_s != 'id'}.map(&:to_sym)
      attrs.keys.each { |key| attrs[key.to_sym] = attrs.delete(key)}
      cols.each do |c|
        if !attrs.has_key?(c)
          attrs[c] = nil 
        end
      end

      attrs.each do |key, val| 
        if !self.class.method_defined?(key)
          raise "No method `#{key}` for #{self.class.name.capitalize} instance." 
        end
        send("#{key}=", val) if key.to_s != 'id'
        @id = val if key.to_s == 'id'
      end
     
    end

    def update_with(attrs={})
      return false if id.nil?
      
      allowed_attrs = attrs.select do |k, v| 
        self.class.fetch_columns.include?(k.to_s) && k.to_s != 'id'
      end

      allowed_attrs.each{|k, v| send("#{k}=", v)}

      filtered_attrs = self.class.filtered_attrs
      @errors = self.class.check_errors(self, filtered_attrs)
      
      return false if errors.to_a.any?

      values = allowed_attrs.map{|k,v| "`#{k}` = '#{v}'"}.join(', ')
      sql = "UPDATE #{self.class.table_name} SET #{values} WHERE id=#{id}"
      self.class.exec(sql)
      return true
    rescue
      false 
    end

    def save
      filtered_attrs = self.class.filtered_attrs
      @errors = self.class.check_errors(self, filtered_attrs)
      return false if errors.to_a.any?
      if id.nil?
        items = filtered_attrs.reduce({k: [], v: []}) do |res, k|
          res[:k] << "`#{k}`"
          res[:v] << "'#{send(k)}'"
          res
        end 
        values = "(#{items[:k].join(', ')}) VALUES (#{items[:v].join(',')})"
        sql = "INSERT INTO #{self.class.table_name} #{values}"
        self.class.exec(sql)
        @id = @@db_client.last_id
        return true
      else
        attrs = filtered_attrs.reduce({}) do |res, c|
          res[c] = send(c)
          res
        end
        update_with(attrs)
      end
    rescue => e
      puts e
      false  
    end

    def errors
      (@errors ||= []).compact.uniq
    end


    class << self

      def setup
        options = yield
        @@db_client = Mysql2::Client.new(
          host: options[:host], 
          username: options[:username], 
          password: options[:password], 
          database: options[:database]
        )
      end


      def method_missing(method, *args)
        return where($1 => args.first).first if method.to_s =~ /^get_by_(.+)/
        super
      end

      def check_errors(obj, fields)
        (@validations || []).map do |validation| 
          field = validation[0].to_s
          msg = validation[1]
          block = validation[2]
          if fields.include? field
            if block
              evaluation = block.call(obj)
              {field: field, msg: msg[:msg]} if !evaluation
            end
          end
        end.compact
      end

      def validate(field, message, &block)
        validation = [field, message]
        validation << block if block_given?
        @validations ||= []
        @validations << validation
      end

      def belongs_to(model)
        define_method(model) do
          # binding.pry
          foreign_key = "#{model}_id"
          Object.const_get(model.to_s.capitalize)
            .where("id = #{send(foreign_key)}").first
        end
      end

      def has_one(model, **fk) 
        method_name = model
        method_name = fk[:as] if fk[:as]
        define_method(method_name) do
          # binding.pry
          foreign_key = "#{model}_id"
          foreign_key = fk[:via] if fk[:via]
          Object.const_get("#{model.to_s.capitalize}")
            .where("id = #{send(foreign_key)}").first
        end
      end

      def has_many(model, **fk)
        self.define_singleton_method(:via) do
          fk[:via] 
        end
        method_name = model
        method_name = fk[:as] if fk[:as]
        singular = model.to_s.chop
        # p method_name
        define_method(method_name) do
          foreign_key = "#{self.class.name.downcase}_id"
          foreign_key = fk[:via] if !fk[:via].nil?
          Object.const_get(singular.capitalize)
            .where("#{foreign_key} = #{send(:id)}")
        end
      end

      def build_entity_methods
        columns(*fetch_columns)
      end

      def filtered_attrs
        fetch_columns.select{|f| f != 'id'}
      end

      def fetch_columns
        cols = exec("EXPLAIN #{table_name}")
        cols.map{|row| row['Field'] }
      end

      def first
        at(:first)
      end

      def last
        at(:last)
      end

      def at(position)
        if position == :first
          order = 'ASC'
        elsif position == :last
          order = 'DESC'
        end

        return nil unless order
        
        sql = "SELECT * FROM #{table_name} ORDER BY id #{order} LIMIT 1"
        new exec(sql).first
      end

      def find(id)
        where(id: id).first
      end

      def all
        sql = "SELECT * FROM #{table_name}"
        exec(sql).map{|row| new(row)}
      end

      def joins(model, cond=nil)
        fk = "#{table_name.to_s.chop}_id"
        fk = self.via.to_s if self.via
        sql = "SELECT * FROM #{table_name} INNER JOIN #{model.to_s} ON #{model.to_s}.#{fk} = #{table_name}.id"
        sql += " WHERE #{cond}" if cond
        p sql
        exec(sql).map{|row| binding.pry; new(row)}
      end

      def condition_builder(cond)
        res = cond.reduce('') do |res, each_cond|
          attr = each_cond.first
          value = each_cond.last
          operator = value.is_a?(Array) ? "IN (#{value.map{|x|"'#{x}'"}.join(', ')})": "= '#{value}'"
          res += "#{attr.to_s} #{operator} AND "
        end
        res[0...-5]
      end

      def where(cond)
        cond = condition_builder(cond) if cond.is_a?(Hash)
        sql = "SELECT * FROM #{table_name} WHERE #{cond}"
        puts sql
        exec(sql).map{|row| new(row)}
      end

      def exec(sql)
        @@db_client.query(sql)
      end

      def create(attrs)
        obj = new(attrs)
        obj.save ? obj : nil
      end

      def columns(*args)
        args.each do |f| 
          attr_accessor(f) if f != 'id'  
          attr_reader(f) if f == 'id'
        end
      end

      def table_name
        return "#{self.to_s.downcase}s" if superclass.to_s == 'MysqlSimpleOrm::Base'
        "#{superclass.to_s.downcase}s"
      end

    end
  end
end