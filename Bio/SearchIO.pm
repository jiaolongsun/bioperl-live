# $Id$
#
# BioPerl module for Bio::SearchIO
#
# Please direct questions and support issues to <bioperl-l@bioperl.org> 
#
# Cared for by Jason Stajich <jason-at-bioperl.org>
#
# Copyright Jason Stajich
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::SearchIO - Driver for parsing Sequence Database Searches 
(BLAST, FASTA, ...)

=head1 SYNOPSIS

   use Bio::SearchIO;
   # format can be 'fasta', 'blast', 'exonerate', ...
   my $searchio = Bio::SearchIO->new( -format => 'blastxml',
                                     -file   => 'blastout.xml' );
   while ( my $result = $searchio->next_result() ) {
       while( my $hit = $result->next_hit ) {
        # process the Bio::Search::Hit::HitI object
           while( my $hsp = $hit->next_hsp ) { 
            # process the Bio::Search::HSP::HSPI object
           }
       }
   }


=head1 DESCRIPTION

This is a driver for instantiating a parser for report files from
sequence database searches. This object serves as a wrapper for the
format parsers in Bio::SearchIO::* - you should not need to ever
use those format parsers directly. (For people used to the SeqIO
system it, we are deliberately using the same pattern).

Once you get a SearchIO object, calling next_result() gives you back
a L<Bio::Search::Result::ResultI> compliant object, which is an object that
represents one Blast/Fasta/HMMER whatever report.

A list of module names and formats is below:

  blast      BLAST (WUBLAST, NCBIBLAST,bl2seq)   
  fasta      FASTA -m9 and -m0
  blasttable BLAST -m9 or -m8 output (both NCBI and WUBLAST tabular)
  megablast  MEGABLAST
  psl        UCSC PSL format
  waba       WABA output
  axt        AXT format
  sim4       Sim4
  hmmer      HMMER hmmpfam and hmmsearch
  exonerate  Exonerate CIGAR and VULGAR format
  blastxml   NCBI BLAST XML
  wise       Genewise -genesf format

Also see the SearchIO HOWTO:
http://bioperl.open-bio.org/wiki/HOWTO:SearchIO

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org                  - General discussion
  http://bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Support 
 
Please direct usage questions or support issues to the mailing list:
  
L<bioperl-l@bioperl.org>
  
rather than to the module maintainer directly. Many experienced and 
reponsive experts will be able look at the problem and quickly 
address it. Please include a thorough description of the problem 
with code and data examples if at all possible.

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via the
web:

  http://bugzilla.open-bio.org/

=head1 AUTHOR - Jason Stajich & Steve Chervitz

Email jason-at-bioperl.org
Email sac-at-bioperl.org

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::SearchIO;
use strict;

# Object preamble - inherits from Bio::Root::IO

use Bio::SearchIO::SearchResultEventBuilder;

# Special exception class for exceptions during parsing.
# End users should not ever see these.
# For an example of usage, see blast.pm.
@Bio::SearchIO::InternalParserError::ISA = qw(Bio::Root::Exception);

use Symbol;

use base qw(Bio::Root::IO Bio::Event::EventGeneratorI Bio::AnalysisParserI);

=head2 new

 Title   : new
 Usage   : my $obj = Bio::SearchIO->new();
 Function: Builds a new Bio::SearchIO object 
 Returns : Bio::SearchIO initialized with the correct format
 Args    : -file           => $filename
           -format         => format
           -fh             => filehandle to attach to
           -result_factory => Object implementing Bio::Factory::ObjectFactoryI
           -hit_factory    => Object implementing Bio::Factory::ObjectFactoryI
           -hsp_factory    => Object implementing Bio::Factory::ObjectFactoryI
           -writer         => Object implementing Bio::SearchIO::SearchWriterI
           -output_format  => output format, which will dynamically load writer

See L<Bio::Factory::ObjectFactoryI>, L<Bio::SearchIO::SearchWriterI>

Any factory objects in the arguments are passed along to the
SearchResultEventBuilder object which holds these factories and sets
default ones if none are supplied as arguments.

=cut

sub new {
  my($caller,@args) = @_;
  my $class = ref($caller) || $caller;
    
  # or do we want to call SUPER on an object if $caller is an
  # object?
  if( $class =~ /Bio::SearchIO::(\S+)/ ) {
    my ($self) = $class->SUPER::new(@args);        
    $self->_initialize(@args);
    return $self;
  } else { 
    my %param = @args;
    @param{ map { lc $_ } keys %param } = values %param; # lowercase keys
    my $format = $param{'-format'} ||
      $class->_guess_format( $param{'-file'} || $ARGV[0] ) || 'blast';

    my $output_format = $param{'-output_format'};
    my $writer = undef;

    if( defined $output_format ) {
        if( defined $param{'-writer'} ) {
            my $dummy = Bio::Root::Root->new();
            $dummy->throw("Both writer and output format specified - not good");
        }

        if( $output_format =~ /^blast$/i ) {
            $output_format = 'TextResultWriter';
        }
        my $output_module = "Bio::SearchIO::Writer::".$output_format;
        $class->_load_module($output_module);
        $writer = $output_module->new(@args);
        push(@args,"-writer",$writer);
    }


    # normalize capitalization to lower case
    $format = "\L$format";
    
    return unless( $class->_load_format_module($format) );
    return "Bio::SearchIO::${format}"->new(@args);
  }
}

=head2 newFh

 Title   : newFh
 Usage   : $fh = Bio::SearchIO->newFh(-file=>$filename,
                                      -format=>'Format')
 Function: does a new() followed by an fh()
 Example : $fh = Bio::SearchIO->newFh(-file=>$filename,
                                      -format=>'Format')
           $result = <$fh>;   # read a ResultI object
           print $fh $result; # write a ResultI object
 Returns : filehandle tied to the Bio::SearchIO::Fh class
 Args    :

=cut

sub newFh {
  my $class = shift;
  return unless my $self = $class->new(@_);
  return $self->fh;
}

=head2 fh

 Title   : fh
 Usage   : $obj->fh
 Function:
 Example : $fh = $obj->fh;      # make a tied filehandle
           $result = <$fh>;     # read a ResultI object
           print $fh $result;   # write a ResultI object
 Returns : filehandle tied to the Bio::SearchIO::Fh class
 Args    :

=cut


sub fh {
  my $self = shift;
  my $class = ref($self) || $self;
  my $s = Symbol::gensym;
  tie $$s,$class,$self;
  return $s;
}

=head2 attach_EventHandler

 Title   : attach_EventHandler
 Usage   : $parser->attatch_EventHandler($handler)
 Function: Adds an event handler to listen for events
 Returns : none
 Args    : Bio::SearchIO::EventHandlerI

See L<Bio::SearchIO::EventHandlerI>

=cut

sub attach_EventHandler{
    my ($self,$handler) = @_;
    return if( ! $handler );
    if( ! $handler->isa('Bio::SearchIO::EventHandlerI') ) {
        $self->warn("Ignoring request to attatch handler ".ref($handler). ' because it is not a Bio::SearchIO::EventHandlerI');
    }
    $self->{'_handler'} = $handler;
    return;
}

=head2 _eventHandler

 Title   : _eventHandler
 Usage   : private
 Function: Get the EventHandler
 Returns : Bio::SearchIO::EventHandlerI
 Args    : none

See L<Bio::SearchIO::EventHandlerI>

=cut

sub _eventHandler{
   my ($self) = @_;
   return $self->{'_handler'};
}

sub _initialize {
    my($self, @args) = @_;
    $self->{'_handler'} = undef;
    # not really necessary unless we put more in RootI
    #$self->SUPER::_initialize(@args);

    # initialize the IO part
    $self->_initialize_io(@args);
    $self->attach_EventHandler(Bio::SearchIO::SearchResultEventBuilder->new(@args));
    $self->{'_reporttype'} = '';
    $self->{_notfirsttime} = 0;
    my ( $writer ) = $self->_rearrange([qw(WRITER)], @args);

    $self->writer( $writer ) if $writer;
}

=head2 next_result

 Title   : next_result
 Usage   : $result = stream->next_result
 Function: Reads the next ResultI object from the stream and returns it.

           Certain driver modules may encounter entries in the stream that
           are either misformatted or that use syntax not yet understood
           by the driver. If such an incident is recoverable, e.g., by
           dismissing a feature of a feature table or some other non-mandatory
           part of an entry, the driver will issue a warning. In the case
           of a non-recoverable situation an exception will be thrown.
           Do not assume that you can resume parsing the same stream after
           catching the exception. Note that you can always turn recoverable
           errors into exceptions by calling $stream->verbose(2) (see
           Bio::Root::RootI POD page).
 Returns : A Bio::Search::Result::ResultI object
 Args    : n/a

See L<Bio::Root::RootI>

=cut

sub next_result {
   my ($self) = @_;
   $self->throw_not_implemented;
}

=head2 write_result

 Title   : write_result
 Usage   : $stream->write_result($result_result, @other_args)
 Function: Writes data from the $result_result object into the stream.
         : Delegates to the to_string() method of the associated 
         : WriterI object.
 Returns : 1 for success and 0 for error
 Args    : Bio::Search:Result::ResultI object,
         : plus any other arguments for the Writer
 Throws  : Bio::Root::Exception if a Writer has not been set.

See L<Bio::Root::Exception>

=cut

sub write_result {
   my ($self, $result, @args) = @_;

   if( not ref($self->{'_result_writer'}) ) {
       $self->throw("ResultWriter not defined.");
   }
   @args = $self->{'_notfirsttime'} unless( @args );

   my $str = $self->writer->to_string( $result, @args);
   $self->{'_notfirsttime'} = 1;
   $self->_print( "$str" ) if defined $str;
   
   $self->flush if $self->_flush_on_write && defined $self->_fh;
   return 1;
}

=head2 write_report

 Title   : write_report
 Usage   : $stream->write_report(SearchIO stream, @other_args)
 Function: Writes data directly from the SearchIO stream object into the
         : writer.  This is mainly useful if one has multiple ResultI objects
         : in a SearchIO stream and you don't want to reiterate header/footer
         : between each call.
 Returns : 1 for success and 0 for error
 Args    : Bio::SearchIO stream object,
         : plus any other arguments for the Writer
 Throws  : Bio::Root::Exception if a Writer has not been set.

See L<Bio::Root::Exception>

=cut

sub write_report {
   my ($self, $result, @args) = @_;

   if( not ref($self->{'_result_writer'}) ) {
       $self->throw("ResultWriter not defined.");
   }
   @args = $self->{'_notfirsttime'} unless( @args );

   my $str = $self->writer->to_string( $result, @args);
   $self->{'_notfirsttime'} = 1;
   $self->_print( "$str" ) if defined $str;
   
   $self->flush if $self->_flush_on_write && defined $self->_fh;
   return 1;
}


=head2 writer

 Title   : writer
 Usage   : $writer = $stream->writer;
 Function: Sets/Gets a SearchWriterI object to be used for this searchIO.
 Returns : 1 for success and 0 for error
 Args    : Bio::SearchIO::SearchWriterI object (when setting)
 Throws  : Bio::Root::Exception if a non-Bio::SearchIO::SearchWriterI object
           is passed in.

=cut

sub writer {
    my ($self, $writer) = @_;
    if( ref($writer) and $writer->isa( 'Bio::SearchIO::SearchWriterI' )) {
        $self->{'_result_writer'} = $writer;
    }
    elsif( defined $writer ) {
        $self->throw("Can't set ResultWriter. Not a Bio::SearchIO::SearchWriterI: $writer");
    }
    return $self->{'_result_writer'};
}


=head2 result_count

 Title   : result_count
 Usage   : $num = $stream->result_count;
 Function: Gets the number of Blast results that have been successfully parsed
           at the point of the method call.  This is not the total # of results
           in the file.
 Returns : integer
 Args    : none
 Throws  : none

=cut

sub result_count {
    my $self = shift;
    $self->throw_not_implemented;
}


=head2 _load_format_module

 Title   : _load_format_module
 Usage   : *INTERNAL SearchIO stuff*
 Function: Loads up (like use) a module at run time on demand
 Example : 
 Returns : 
 Args    : 

=cut

sub _load_format_module {
  my ($self,$format) = @_;
  my $module = "Bio::SearchIO::" . $format;
  my $ok;
  
  eval {
      $ok = $self->_load_module($module);
  };
  if ( $@ ) {
      print STDERR <<END;
$self: $format cannot be found
Exception $@
For more information about the SearchIO system please see the SearchIO docs.
This includes ways of checking for formats at compile time, not run time
END
  ;
  }
  return $ok;
}

=head2 _get_seq_identifiers

 Title   : _get_seq_identifiers
 Usage   : my ($gi, $acc,$ver) = &_get_seq_identifiers($id)
 Function: Private function to get the gi, accession, version data
           for an ID (if it is in NCBI format)
 Returns : 3-pule of gi, accession, version
 Args    : ID string to process (NCBI format)


=cut

sub _get_seq_identifiers {
    my ($self, $id) = @_;

    return unless defined $id;
    my ($gi, $acc, $version );
    if ( $id =~ /^gi\|(\d+)\|/ ) {
        $gi = $1;
    }
    if ( $id =~ /(gb|emb|dbj|sp|pdb|bbs|ref|lcl)\|(.*)\|(.*)/ ) {
        ( $acc, $version ) = split /\./, $2;
    }
    elsif ( $id =~ /(pir|prf|pat|gnl)\|(.*)\|(.*)/ ) {
        ( $acc, $version ) = split /\./, $3;
    }
    else {

        #punt, not matching the db's at ftp://ftp.ncbi.nih.gov/blast/db/README
        #Database Name                     Identifier Syntax
        #============================      ========================
        #GenBank                           gb|accession|locus
        #EMBL Data Library                 emb|accession|locus
        #DDBJ, DNA Database of Japan       dbj|accession|locus
        #NBRF PIR                          pir||entry
        #Protein Research Foundation       prf||name
        #SWISS-PROT                        sp|accession|entry name
        #Brookhaven Protein Data Bank      pdb|entry|chain
        #Patents                           pat|country|number
        #GenInfo Backbone Id               bbs|number
        #General database identifier           gnl|database|identifier
        #NCBI Reference Sequence           ref|accession|locus
        #Local Sequence identifier         lcl|identifier
        $acc = $id;
    }
    return ($gi, $acc, $version );
}

=head2 _guess_format

 Title   : _guess_format
 Usage   : $obj->_guess_format($filename)
 Function:
 Example :
 Returns : guessed format of filename (lower case)
 Args    :

=cut

sub _guess_format {
   my $class = shift;
   return unless $_ = shift;
   return 'blast'   if (/\.(blast|t?bl\w)$/i );
   return 'fasta' if (/\.
		      (?: t? fas (?:ta)? |
		       m\d+ |
		       (?: t? (?: fa |  fx |  fy |  ff |  fs ) ) |
		       (?: (?:ss | os | ps) (?:earch)? ))
		      $/ix );
   return 'blastxml' if ( /\.(blast)?xml$/i);
   return 'exonerate' if ( /\.exon(erate)?/i );
}

sub close { 
    my $self = shift;    

    if( $self->writer ) {
        $self->_print($self->writer->end_report());
	$self->{'_result_writer'}= undef;
    }
    $self->SUPER::close(@_);
}

sub DESTROY {
    my $self = shift;
    $self->close() if defined $self->_fh;
    $self->SUPER::DESTROY;
}

sub TIEHANDLE {
  my $class = shift;
  return bless {processor => shift}, $class;
}

sub READLINE {
  my $self = shift;
  return $self->{'processor'}->next_result() unless wantarray;
  my (@list, $obj);
  push @list, $obj while $obj = $self->{'processor'}->next_result();
  return @list;
}

sub PRINT {
  my $self = shift;
  $self->{'processor'}->write_result(@_);
}


1;

__END__
