-- The project table stores a list of participating 
wikiprojects

create table projects ( 

    p_project         varchar(63) not null,
        -- project name

    p_timestamp       binary(14) not null,
        -- last time project data was updated

    p_wikipage        varchar(255),
        -- homepage on the wiki for this project

    p_parent          varchar(63),
        -- parent project (for task forces)

    primary key (p_project)
) default character set 'utf8' 
  engine = InnoDB;


-- The ratings table stores the ratings data. Each article will
-- be listed once per project that assessed it. 

create table ratings ( 

    r_project               varchar(63)  not null,
        -- project name

    r_article               varchar(255) not null,
        -- article title

    r_quality               varchar(63),
        -- quality rating

    r_quality_timestamp     binary(14),
        -- time when quality rating was assigned
        --   NOTE: a revid can be obtained from timestamp via API

    r_importance            varchar(63),
        -- importance rating

    r_importance_timestamp  binary(20),
        -- time when importance rating was assigned

    primary key (r_project, r_article)
) default character set 'utf8'
  engine = InnoDB;



-- The categories table stores a list of all ratings 
-- assigned by a particular project

create table categories ( 

    c_project         varchar(63)  not null,
        -- project name

    c_type	      varchar(16)  not null,
        -- what type of rating - 'quality' or 'importance'

    c_rating          varchar(63)  not null,
        -- name of the rating (e.g. B-Class)
  
    c_category        varchar(255) not null,
        -- category used to get pages that are assigned this rating

    c_ranking           int unsigned not null,
        -- sortkey, used when creating tables 

    primary key (c_project, c_type, c_rating)
) default character set 'utf8'
  engine = InnoDB;



-- The logging table has one log entry for each change of an article. 
-- Changing both quality and importance will create two log entries. 

create table logging ( 
    l_project        varchar(63)  not null,   
       -- project name

    l_article        varchar(255) not null,
       -- article name

    l_action         varchar(20) character set ascii not null,
       -- type of log entry (e.g. 'quality')

       -- NOTE: this is ASCII because of maximum index key
       -- length constraints interacting with utf-8 fields in  
       -- mysql. The primary key for this table is just under the limit. 
 
    l_timestamp      binary(14)  not null,
       -- timestamp when log entry was added

    l_old            varchar(63),
       -- old value (e.g. B-Class)

    l_new            varchar(63),
       -- new value (e.g. GA-Class)

    l_revision_timestamp  binary(14)  not null,
       -- timestamp when page was edited

    key (l_project, l_article, l_action, l_timestamp)
) default charset = 'utf8'
  engine = InnoDB;
