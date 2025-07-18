module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def searchable_by(*fields, using:)
      define_method :search_fields do
        fields
      end

      define_method :search_values do
        fields.map do
          value = send(it)
          value.respond_to?(:to_plain_text) ? value.to_plain_text : value
        end
      end

      define_method :search_table do
        using
      end

      after_create_commit :create_in_search_index
      after_update_commit :update_in_search_index
      after_destroy_commit :remove_from_search_index

      scope :search, ->(query) do
        query = Search::Query.wrap(query)

        base = joins("join #{using} idx on #{table_name}.id = idx.rowid")

        if query.valid?
          base.where("#{using} match ?", query.to_s)
        else
          base.none
        end
      end
    end
  end

  def reindex
    update_in_search_index
  end

  private
    def create_in_search_index
      fields_sql = [ "rowid", *search_fields ].join(", ")
      placeholders = ([ "?" ] * (search_fields.size + 1)).join(", ")
      values = [ id, *search_values ]

      execute_sql_with_binds(
        "insert into #{search_table}(#{fields_sql}) values (#{placeholders})",
        *values
      )
    end

    def update_in_search_index
      transaction do
        set_clause = search_fields.map { |field| "#{field} = ?" }.join(", ")
        binds = search_values + [ id ]

        updated = execute_sql_with_binds(
          "update #{search_table} set #{set_clause} where rowid = ?",
          *binds
        )

        create_in_search_index unless updated
      end
    end

    def remove_from_search_index
      execute_sql_with_binds "delete from #{search_table} where rowid = ?", id
    end

    def execute_sql_with_binds(*statement)
      self.class.connection.execute self.class.sanitize_sql(statement)
      self.class.connection.raw_connection.changes.nonzero?
    end
end
